extends Object
## Coordinates metadata lookup and lot content installation.

const _EnhancedFileSystemResolver = Semperland__Persona.Utils.EnhancedFileSystemResolver
const _LotContentsDownloader = EnhancedFileSystemResolver.Utils.LotContentsDownloader
const _LotMetadataDownloader = EnhancedFileSystemResolver.Utils.LotMetadataDownloader

const DEFAULT_RESOLVER_CACHE_NAME := "persona_lot_data"
const DEFAULT_RESOLVER_CACHE_MAX_DISPOSAL_SIZE := 128

var _lot_contents_downloader: _LotContentsDownloader = null
var _lot_metadata_downloader: _LotMetadataDownloader = null
var _target_directory: String = ""
var _resolver_cache_name: String = ""
var _resolver_cache_max_disposal_size: int = DEFAULT_RESOLVER_CACHE_MAX_DISPOSAL_SIZE

func _init(
	lot_contents_downloader: _LotContentsDownloader,
	lot_metadata_downloader: _LotMetadataDownloader,
	target_directory: String,
	resolver_cache_name: String = DEFAULT_RESOLVER_CACHE_NAME,
	resolver_cache_max_disposal_size: int = DEFAULT_RESOLVER_CACHE_MAX_DISPOSAL_SIZE
):
	_lot_contents_downloader = lot_contents_downloader
	_lot_metadata_downloader = lot_metadata_downloader
	_target_directory = _normalize_user_directory(target_directory)
	_resolver_cache_name = resolver_cache_name.strip_edges()
	if _resolver_cache_name == "":
		_resolver_cache_name = DEFAULT_RESOLVER_CACHE_NAME
	_resolver_cache_max_disposal_size = max(resolver_cache_max_disposal_size, 0)

## Downloads all requested lots. Calls callback only if at least one lot was
## downloaded successfully. The callback may be regular or async.
func download_lots(ns: Array[int], callback: Callable) -> bool:
	var downloaded := false
	for n in ns:
		if await _download_lot(n):
			downloaded = true
	if downloaded and callback.is_valid():
		@warning_ignore("redundant_await")
		await callback.call()
	return downloaded

func _download_lot(n: int) -> bool:
	if n <= 0:
		return false
	var resolver := _persona_resolver()
	if resolver == null:
		return false
	if _lot_contents_downloader == null or _lot_metadata_downloader == null:
		return false

	var metadata := await _lot_metadata_downloader.call("download_lot", n)
	if not _is_ok(metadata):
		return false

	var metadata_value = _value(metadata)
	if not (metadata_value is Dictionary):
		return false

	var name := String(metadata_value.get("name", "")).strip_edges()
	var url := String(metadata_value.get("url", "")).strip_edges()
	if name == "" or url == "":
		return false

	var resolver_key := await _ensure_resolver_for_url(resolver, n, url)
	if resolver_key == "":
		return false

	if resolver.has_lot(n):
		return true
	return resolver.add_lot(n, resolver_key)

func _ensure_resolver_for_url(resolver: _EnhancedFileSystemResolver, n: int, url: String) -> String:
	if url.begins_with("local://"):
		if resolver.has_resolver(url):
			return url
		return ""

	if not _is_downloadable_url(url):
		return ""

	var subdirectory := _subdirectory_for_url(url)
	var target_directory := _target_directory.path_join(subdirectory)
	if not resolver.has_resolver(target_directory):
		var download := await _lot_contents_downloader.call("download_lot", n, url, subdirectory)
		if not _is_ok(download):
			return ""
		var downloaded_directory := _downloaded_directory(download)
		if downloaded_directory != target_directory:
			return ""
		resolver.add_resolver(
			target_directory,
			_resolver_cache_name,
			_resolver_cache_max_disposal_size
		)

	if resolver.has_resolver(target_directory):
		return target_directory
	return ""

func _persona_resolver():
	var resolver = AlephVault__WindRose__REFMAP.Visuals.People.resolver
	if resolver is _EnhancedFileSystemResolver and is_instance_valid(resolver):
		return resolver
	return null

func _is_downloadable_url(url: String) -> bool:
	return url.begins_with("http://") or url.begins_with("https://") or url.begins_with("ipfs://")

func _subdirectory_for_url(url: String) -> String:
	return "lot_data_" + url.sha256_text().substr(0, 16)

func _downloaded_directory(response: Dictionary) -> String:
	var value = _value(response)
	if not (value is Dictionary):
		return ""
	return String(value.get("directory", "")).strip_edges()

## Trims trailing slashes while preserving the user:// root spelling.
func _normalize_user_directory(path: String) -> String:
	var normalized := path.strip_edges()
	while normalized.ends_with("/") and normalized != "user://":
		normalized = normalized.trim_suffix("/")
	return normalized

func _is_ok(response: Variant) -> bool:
	return response is Dictionary and bool(response.get("ok", false))

func _value(response: Variant):
	if not (response is Dictionary):
		return null
	return response.get("value")
