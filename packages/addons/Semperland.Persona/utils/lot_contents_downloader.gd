extends Object
## Downloads, validates, and installs zipped Persona lot contents.
##
## A lot archive is expected to contain REFMAP-compatible runtime assets with
## two top-level directories: Female and Male. If those directories are nested
## under one or more archive wrapper directories, this downloader finds them and
## installs only those two directories into the requested user:// subdirectory.
##
## All methods return dictionaries shaped as:
## - {"ok": true, "value": ...}
## - {"ok": false, "error": ...}

## MIME types accepted from the HEAD response before downloading the archive.
const ZIP_MIME_TYPES := {
	"application/zip": true,
	"application/x-zip-compressed": true,
	"multipart/x-zip": true,
}

## Directory names required by the Persona filesystem resolver layout.
const REQUIRED_DIRECTORIES := ["Female", "Male"]

var _max_size: int = 0
var _head_timeout: float = 0
var _download_timeout: float = 0
var _target_directory: String = ""
var _ipfs_gateway: String = ""
var _ipfs_gateway_valid: bool = true

func _init(
	max_size: int,
	head_timeout: float,
	download_timeout: float,
	target_directory: String,
	ipfs_gateway: String = ""
):
	_max_size = max_size
	_head_timeout = head_timeout
	_download_timeout = download_timeout
	_target_directory = _normalize_user_directory(target_directory)
	var normalized_ipfs_gateway := _normalize_ipfs_gateway(ipfs_gateway)
	_ipfs_gateway_valid = ipfs_gateway.strip_edges() == "" or normalized_ipfs_gateway != ""
	_ipfs_gateway = normalized_ipfs_gateway

## Downloads a lot archive, validates it, unpacks it, and installs its Female
## and Male directories into target_directory/subdirectory.
##
## lot_id must be positive and is used only to name temporary files.
## url must be http://, https://, or a valid ipfs:// URL.
## The configured target_directory must already exist and must be a valid user:// path.
## ipfs:// URLs are resolved through the configured IPFS gateway before download.
## subdirectory must be a single directory name, not a path.
##
## The final subdirectory may be missing or empty. If it already contains files,
## this method aborts instead of overwriting or deleting existing user data.
func download_lot(lot_id: int, url: String, subdirectory: String) -> Dictionary:
	var validation := _validate_arguments(lot_id, url, subdirectory)
	if not _is_ok(validation):
		return validation
	var download_url: String = _value(validation)

	var final_directory := _target_directory.path_join(subdirectory)
	var zip_path := _target_directory.path_join(".lot_%s.zip" % lot_id)
	var extract_directory := _target_directory.path_join(".lot_%s_extract" % lot_id)
	var final_directory_existed := DirAccess.dir_exists_absolute(final_directory)

	# Clear only downloader-owned temporary paths from previous interrupted runs.
	_cleanup_path(zip_path)
	_cleanup_path(extract_directory)

	var head := await _request(download_url, HTTPClient.METHOD_HEAD, "", 0, max(_head_timeout, 0.0))
	if not _is_ok(head):
		return head

	var head_check := _validate_head(_value(head), _max_size)
	if not _is_ok(head_check):
		return head_check

	var download := await _download(download_url, zip_path, _max_size, max(_download_timeout, 0.0))
	if not _is_ok(download):
		_cleanup_path(zip_path)
		return download

	var zip_check := _assert_zip_file(zip_path)
	if not _is_ok(zip_check):
		_cleanup_path(zip_path)
		return zip_check

	var install := _install_zip(zip_path, extract_directory, final_directory)
	_cleanup_path(zip_path)
	if not _is_ok(install):
		_cleanup_path(extract_directory)
		if DirAccess.dir_exists_absolute(final_directory) and (not final_directory_existed or _directory_is_empty(final_directory)):
			_cleanup_path(final_directory)
		return install

	return _success({
		"lot_id": lot_id,
		"directory": final_directory,
	})

## Performs local argument validation before any network or filesystem mutation.
func _validate_arguments(lot_id: int, url: String, subdirectory: String) -> Dictionary:
	if lot_id <= 0:
		return _failed("invalid_lot_id")
	var resolved_url := _resolve_download_url(url)
	if not _is_ok(resolved_url):
		return resolved_url
	var target_check := _validate_target_directory(_target_directory)
	if not _is_ok(target_check):
		return target_check
	if not _is_valid_subdirectory_name(subdirectory):
		return _failed("invalid_subdirectory")
	return resolved_url

## Validates the HEAD response: successful HTTP status, zip MIME type, and
## Content-Length within the optional byte limit.
func _validate_head(response: Dictionary, max_size: int) -> Dictionary:
	var response_code := int(response.get("response_code", 0))
	if response_code < 200 or response_code >= 300:
		return _failed({"code": "head_request_failed", "http_status": response_code})

	var headers: Dictionary = response.get("headers", {})
	var mime := _header_value(headers, "content-type").split(";")[0].strip_edges().to_lower()
	if not ZIP_MIME_TYPES.has(mime):
		return _failed({"code": "invalid_mime", "mime": mime})

	var content_length := _header_value(headers, "content-length").strip_edges()
	if content_length == "":
		if max_size > 0:
			return _failed("missing_content_length")
		return _success({"size": -1, "mime": mime})
	if not content_length.is_valid_int():
		return _failed("missing_content_length")
	var size := content_length.to_int()
	if size < 0:
		return _failed("invalid_content_length")
	if max_size > 0 and size > max_size:
		return _failed({"code": "file_too_large", "size": size, "max_size": max_size})
	return _success({"size": size, "mime": mime})

## Executes one HTTP request through a temporary HTTPRequest node attached to
## the active scene root. This keeps the utility instantiable as a plain Object
## while still using Godot's node-based HTTP API.
func _request(url: String, method: int, download_file: String, body_size_limit: int, timeout: float) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return _failed("missing_scene_tree")

	var http := HTTPRequest.new()
	tree.root.add_child(http)
	http.timeout = timeout
	http.download_file = download_file
	if body_size_limit > 0:
		http.body_size_limit = body_size_limit

	var request_error := http.request(url.strip_edges(), PackedStringArray(), method)
	if request_error != OK:
		http.queue_free()
		return _failed({"code": "request_start_failed", "error": request_error})

	var result = await http.request_completed
	http.queue_free()
	if not (result is Array) or result.size() < 4:
		return _failed("invalid_http_response")
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return _failed({"code": "http_request_failed", "result": int(result[0])})

	return _success({
		"response_code": int(result[1]),
		"headers": _parse_headers(result[2]),
		"body": result[3],
	})

## Downloads the archive into zip_path and verifies the saved file exists and
## respects max_size. HTTPRequest.body_size_limit should stop oversized bodies,
## but the final file size is checked again after writing.
func _download(url: String, zip_path: String, max_size: int, timeout: float) -> Dictionary:
	var result := await _request(url, HTTPClient.METHOD_GET, zip_path, max_size, timeout)
	if not _is_ok(result):
		return result
	var response_code := int(_value(result).get("response_code", 0))
	if response_code < 200 or response_code >= 300:
		return _failed({"code": "download_failed", "http_status": response_code})
	if not FileAccess.file_exists(zip_path):
		return _failed("download_missing")
	if max_size > 0:
		var actual_size := _file_size(zip_path)
		if actual_size < 0:
			return _failed("download_size_unavailable")
		if actual_size > max_size:
			return _failed({"code": "file_too_large", "size": actual_size, "max_size": max_size})
	return _success(null)

## Opens the downloaded file as a ZIP archive and rejects empty archives.
func _assert_zip_file(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var error := reader.open(zip_path)
	if error != OK:
		reader.close()
		return _failed({"code": "invalid_zip", "error": error})
	var files := reader.get_files()
	reader.close()
	if files.is_empty():
		return _failed("empty_zip")
	return _success(null)

## Extracts into a temporary directory, finds the directory that directly owns
## Female and Male, then copies just those directories to the final destination.
## The final destination is only replaced after extraction and layout validation
## have both succeeded.
func _install_zip(zip_path: String, extract_directory: String, final_directory: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(final_directory) and not _directory_is_empty(final_directory):
		return _failed("target_subdirectory_not_empty")

	var make_extract := DirAccess.make_dir_recursive_absolute(extract_directory)
	if make_extract != OK:
		return _failed({"code": "extract_directory_failed", "error": make_extract})

	var extract := _extract_zip(zip_path, extract_directory)
	if not _is_ok(extract):
		return extract

	var content_root_check := _find_content_root(extract_directory)
	if not _is_ok(content_root_check):
		return content_root_check
	var content_root: String = _value(content_root_check)

	if DirAccess.dir_exists_absolute(final_directory):
		_cleanup_path(final_directory)
	var make_final := DirAccess.make_dir_recursive_absolute(final_directory)
	if make_final != OK:
		return _failed({"code": "target_subdirectory_failed", "error": make_final})

	for required in REQUIRED_DIRECTORIES:
		var from := content_root.path_join(required)
		var to := final_directory.path_join(required)
		var copy := _copy_directory(from, to)
		if not _is_ok(copy):
			_cleanup_path(final_directory)
			return copy

	_cleanup_path(extract_directory)
	return _success(final_directory)

## Extracts all ZIP entries into extract_directory. Entry paths are validated
## before writing so archives cannot escape the target directory with absolute
## paths, Windows drive paths, or .. traversal.
func _extract_zip(zip_path: String, extract_directory: String) -> Dictionary:
	var reader := ZIPReader.new()
	var open_error := reader.open(zip_path)
	if open_error != OK:
		reader.close()
		return _failed({"code": "invalid_zip", "error": open_error})

	for file_path in reader.get_files():
		var safe_path := _safe_zip_entry_path(String(file_path))
		if safe_path == "":
			reader.close()
			return _failed({"code": "unsafe_zip_entry", "path": String(file_path)})
		if safe_path.ends_with("/"):
			var dir_error := DirAccess.make_dir_recursive_absolute(extract_directory.path_join(safe_path))
			if dir_error != OK:
				reader.close()
				return _failed({"code": "directory_create_failed", "path": safe_path, "error": dir_error})
			continue

		var output_path := extract_directory.path_join(safe_path)
		var parent := output_path.get_base_dir()
		var parent_error := DirAccess.make_dir_recursive_absolute(parent)
		if parent_error != OK:
			reader.close()
			return _failed({"code": "directory_create_failed", "path": parent, "error": parent_error})

		var bytes := reader.read_file(file_path)
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		if output == null:
			reader.close()
			return _failed({"code": "file_create_failed", "path": safe_path, "error": FileAccess.get_open_error()})
		output.store_buffer(bytes)
		var file_error := output.get_error()
		output.close()
		if file_error != OK:
			reader.close()
			return _failed({"code": "file_write_failed", "path": safe_path, "error": file_error})

	reader.close()
	return _success(null)

## Returns the first directory under extract_directory that directly contains
## both Female and Male. This handles archives wrapped in an extra root folder.
func _find_content_root(extract_directory: String) -> Dictionary:
	if _has_required_directories(extract_directory):
		return _success(extract_directory)

	var stack := [extract_directory]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			return _failed({"code": "directory_open_failed", "path": current, "error": DirAccess.get_open_error()})
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if dir.current_is_dir() and not name.begins_with("."):
				var child := current.path_join(name)
				if _has_required_directories(child):
					dir.list_dir_end()
					return _success(child)
				stack.push_back(child)
			name = dir.get_next()
		dir.list_dir_end()

	return _failed("missing_male_female_directories")

## Checks whether a directory has the final Persona lot shape.
func _has_required_directories(directory: String) -> bool:
	for required in REQUIRED_DIRECTORIES:
		if not DirAccess.dir_exists_absolute(directory.path_join(required)):
			return false
	return true

## Recursively copies one directory tree. Copying is used instead of renaming
## because the content root may be nested inside temporary wrapper directories.
func _copy_directory(from: String, to: String) -> Dictionary:
	var make_error := DirAccess.make_dir_recursive_absolute(to)
	if make_error != OK:
		return _failed({"code": "directory_create_failed", "path": to, "error": make_error})

	var dir := DirAccess.open(from)
	if dir == null:
		return _failed({"code": "directory_open_failed", "path": from, "error": DirAccess.get_open_error()})

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var source := from.path_join(name)
		var target := to.path_join(name)
		if dir.current_is_dir():
			var copy_subdir := _copy_directory(source, target)
			if not _is_ok(copy_subdir):
				dir.list_dir_end()
				return copy_subdir
		else:
			var copy_error := DirAccess.copy_absolute(source, target)
			if copy_error != OK:
				dir.list_dir_end()
				return _failed({"code": "file_copy_failed", "path": source, "error": copy_error})
		name = dir.get_next()
	dir.list_dir_end()

	return _success(null)

## Removes either a file or directory tree. Callers only pass downloader-owned
## temporary paths or empty/new final directories.
func _cleanup_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	elif DirAccess.dir_exists_absolute(path):
		_remove_directory_recursive(path)

## Recursive directory removal helper used by _cleanup_path.
func _remove_directory_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			_remove_directory_recursive(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

## Returns true only when the directory exists and contains no visible entries.
func _directory_is_empty(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var name := dir.get_next()
	dir.list_dir_end()
	return name == ""

## Normalizes and validates a ZIP entry path. An empty return value means the
## entry is unsafe or invalid and extraction must abort.
func _safe_zip_entry_path(path: String) -> String:
	var normalized := path.replace("\\", "/").strip_edges()
	if normalized == "" or normalized.begins_with("/") or normalized.begins_with("user://") or normalized.find(":") != -1:
		return ""
	var parts := normalized.split("/", false)
	for part in parts:
		if part == "." or part == "..":
			return ""
	return normalized

## Restricts the install target to a single directory name under target_directory.
func _is_valid_subdirectory_name(name: String) -> bool:
	var clean_name := name.strip_edges()
	if clean_name == "" or clean_name != name:
		return false
	if clean_name == "." or clean_name == "..":
		return false
	return clean_name.find("/") == -1 and clean_name.find("\\") == -1 and clean_name.find(":") == -1

## Resolves supported source URLs into HTTP(S) URLs consumable by HTTPRequest.
func _resolve_download_url(url: String) -> Dictionary:
	var clean_url := url.strip_edges()
	if clean_url.begins_with("http://") or clean_url.begins_with("https://"):
		return _success(clean_url)
	if clean_url.begins_with("ipfs://"):
		return _resolve_ipfs_url(clean_url)
	return _failed("invalid_url")

## Converts ipfs://{CID}[/{path}] into {gateway}/ipfs/{CID}[/{path}].
func _resolve_ipfs_url(url: String) -> Dictionary:
	if not _ipfs_gateway_valid:
		return _failed("invalid_ipfs_gateway")
	if _ipfs_gateway == "":
		return _failed("missing_ipfs_gateway")

	var ipfs_path := url.substr("ipfs://".length())
	if not _is_valid_ipfs_path(ipfs_path):
		return _failed("invalid_ipfs_url")

	if _ipfs_gateway.ends_with("/ipfs"):
		return _success(_ipfs_gateway + "/" + ipfs_path)
	return _success(_ipfs_gateway + "/ipfs/" + ipfs_path)

func _is_valid_ipfs_path(path: String) -> bool:
	if path == "" or path.begins_with("/") or path.find("\\") != -1:
		return false
	if path.find("?") != -1 or path.find("#") != -1 or path.find(":") != -1:
		return false

	var parts := path.split("/", true)
	if parts.is_empty() or not _is_valid_ipfs_cid(parts[0]):
		return false

	for i in range(1, parts.size()):
		if not _is_valid_ipfs_path_segment(parts[i]):
			return false
	return true

func _is_valid_ipfs_cid(cid: String) -> bool:
	if cid.length() < 2:
		return false
	return _string_has_only_chars(cid, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

func _is_valid_ipfs_path_segment(segment: String) -> bool:
	if segment == "" or segment == "." or segment == "..":
		return false
	return _string_has_only_chars(
		segment,
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-~"
	)

func _normalize_ipfs_gateway(gateway: String) -> String:
	var normalized := gateway.strip_edges()
	if normalized == "":
		return ""
	if normalized.find("\\") != -1 or normalized.find("?") != -1 or normalized.find("#") != -1:
		return ""
	if normalized.find(" ") != -1:
		return ""
	if normalized.begins_with("http://"):
		return ""
	if not normalized.begins_with("https://"):
		normalized = "https://" + normalized
	while normalized.ends_with("/"):
		normalized = normalized.trim_suffix("/")
	if normalized == "https://" or normalized.find("://", "https://".length()) != -1:
		return ""
	var base_path := normalized.substr("https://".length())
	if base_path == "" or base_path.begins_with("/") or base_path.find("//") != -1 or base_path.find("..") != -1:
		return ""
	if not _string_has_only_chars(
		base_path,
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_~:/"
	):
		return ""
	return normalized

func _string_has_only_chars(value: String, allowed: String) -> bool:
	for i in range(value.length()):
		if allowed.find(value.substr(i, 1)) == -1:
			return false
	return true

## Validates the downloader root as a concrete directory under user://.
func _validate_target_directory(path: String) -> Dictionary:
	var normalized := _normalize_user_directory(path)
	if normalized == "":
		return _failed("invalid_target_directory")
	if not normalized.begins_with("user://"):
		return _failed("invalid_target_directory")

	var relative_path := normalized.substr("user://".length())
	if relative_path.find("\\") != -1 or relative_path.find(":") != -1 or relative_path.begins_with("/"):
		return _failed("invalid_target_directory")

	if relative_path != "":
		var parts := relative_path.split("/", true)
		for part in parts:
			if part == "" or part == "." or part == "..":
				return _failed("invalid_target_directory")

	var user_root := ProjectSettings.globalize_path("user://")
	var global_path := ProjectSettings.globalize_path(normalized)
	if not _is_same_or_child_path(global_path, user_root):
		return _failed("invalid_target_directory")

	if not DirAccess.dir_exists_absolute(normalized):
		return _failed("invalid_target_directory")
	return _success(normalized)

func _is_same_or_child_path(path: String, root: String) -> bool:
	var normalized_path := _normalize_global_directory(path)
	var normalized_root := _normalize_global_directory(root)
	return normalized_path == normalized_root or normalized_path.begins_with(normalized_root + "/")

func _normalize_global_directory(path: String) -> String:
	var normalized := path.replace("\\", "/").strip_edges()
	while normalized.ends_with("/") and normalized != "/":
		normalized = normalized.trim_suffix("/")
	return normalized

## Trims trailing slashes while preserving the user:// root spelling.
func _normalize_user_directory(path: String) -> String:
	var normalized := path.strip_edges()
	while normalized.ends_with("/") and normalized != "user://":
		normalized = normalized.trim_suffix("/")
	return normalized

## Converts HTTPRequest's raw "Name: value" header array to a lowercase-keyed
## dictionary for case-insensitive lookups.
func _parse_headers(raw_headers: PackedStringArray) -> Dictionary:
	var headers := {}
	for raw_header in raw_headers:
		var header := String(raw_header)
		var separator := header.find(":")
		if separator == -1:
			continue
		var key := header.substr(0, separator).strip_edges().to_lower()
		var value := header.substr(separator + 1).strip_edges()
		headers[key] = value
	return headers

## Reads one parsed HTTP header value by case-insensitive key.
func _header_value(headers: Dictionary, key: String) -> String:
	return String(headers.get(key.to_lower(), ""))

## Returns a file's byte length without reading the whole file into memory.
func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size

## Standard response helpers.
func _is_ok(response: Dictionary) -> bool:
	return bool(response.get("ok", false))

func _value(response: Dictionary):
	return response.get("value")

func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value}

func _failed(error: Variant) -> Dictionary:
	return {"ok": false, "error": error}
