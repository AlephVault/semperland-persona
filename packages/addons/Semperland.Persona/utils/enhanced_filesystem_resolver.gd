extends AlephVault__WindRose__REFMAP.Utils.Resolver

const _DefaultResolver = AlephVault__WindRose__REFMAP.Utils.DefaultResolver
const _FileSystemResolver = AlephVault__WindRose__REFMAP.Utils.FileSystemResolver

const DEFAULT_URL: String = "local://default"

var _resolvers: Dictionary = {}
var _default_resolver: _DefaultResolver = null
var _lots: Dictionary = {}
var _lots_by_dir: Dictionary = {}

func _init():
	_default_resolver = _DefaultResolver.new()
	_resolvers[DEFAULT_URL] = _default_resolver
	_lots[1] = DEFAULT_URL
	_lots_by_dir[DEFAULT_URL] = {1: true}

## Registers a lot, which is an index against one of the registered
## root directories and resolvers. Using lots will take place later,
## related to the intended component keys. Many lots can refer to
## the same root path.
func add_lot(n: int, root_directory: String) -> bool:
	if n <= 1 or _lots.has(n) or not _resolvers.has(root_directory):
		return false
	_lots[n] = root_directory
	if not _lots_by_dir.has(root_directory):
		_lots_by_dir[root_directory] = {}
	_lots_by_dir[root_directory][n] = true
	return true

## Registers (instantiates) a filesystem resolver taking the source
## path to be, typically, a user:// URL. It creates and returns the
## instantiated file system resolver.
func add_resolver(
	root_directory: String,
	cache_name: String = "",
	cache_max_disposal_size: int = 128
) -> _FileSystemResolver:
	if not _resolvers.has(root_directory):
		_resolvers[root_directory] = _FileSystemResolver.new(root_directory, cache_name, cache_max_disposal_size)
	return _resolvers[root_directory]

## Registers an existing resolver for a specific local://{name} URL.
func add_local_resolver(name: String, resolver: AlephVault__WindRose__REFMAP.Utils.Resolver):
	var key = "local://" + name
	if not _resolvers.has(key):
		_resolvers[key] = resolver

## Unregisters a resolver by either its directory or local://{name} URL.
func remove_resolver(root_directory: String) -> bool:
	if root_directory == DEFAULT_URL or not _resolvers.has(root_directory):
		return false

	_resolvers.erase(root_directory)
	var lots: Dictionary = _lots_by_dir.get(root_directory, {})
	_lots_by_dir.erase(root_directory)
	for lot in lots.keys():
		_lots.erase(lot)
	return true

## Tells whether a resolver is registered for a directory or local://{name} URL.
func has_resolver(key: String) -> bool:
	return _resolvers.has(key)

## Removes a registered lot.
func remove_lot(n: int) -> bool:
	if n <= 1 or not _lots.has(n):
		return false

	var root_directory: String = _lots[n]
	_lots.erase(n)
	var lots: Dictionary = _lots_by_dir.get(root_directory, {})
	lots.erase(n)
	if lots.is_empty():
		_lots_by_dir.erase(root_directory)
	return true

## Tells whether a lot is registered.
func has_lot(n: int) -> bool:
	return _lots.has(n)

func _resolver_key_for_lot(lot: int) -> String:
	return String(_lots.get(lot, ""))

func _split_lot_key(key: String) -> Array:
	var separator := key.find("/")
	if separator == -1:
		return [_default_resolver, key]

	var lot_key := key.substr(0, separator)
	if not lot_key.is_valid_int():
		return []

	var lot := lot_key.to_int()
	if lot <= 0 or not _lots.has(lot):
		return []

	var resolver_key := _resolver_key_for_lot(lot)
	if not _resolvers.has(resolver_key):
		return []

	return [_resolvers[resolver_key], key.substr(separator + 1)]

## Resolves a non-body component texture. Implementations should
## return Texture2D or null. Callers ignore non-Texture2D values
## and textures whose dimensions are not 128x192.
func resolve(sex: Sex, type: String, key: String, color: int = ComponentColor.Default):
	var resolved_key := _split_lot_key(key)
	if resolved_key.is_empty():
		return null

	return resolved_key[0].resolve(sex, type, resolved_key[1], color)

## Releases a previous successful non-body resolve. If the key comes
## like "{idx}_{color}", this will be handled from the default resolver,
## same as using "1/{idx}_{color}". If the key comes like "{N}/{idx}_{color}"
## but N is not a positive number registered here as a "lot index", then
## nothing will be done. Otherwise, the "{N}/" prefix will be stripped and
## the remaining part will be passed to the resolver associated to the lot
## entry registered as N. Then, un-resolution will take place.
func unresolve(sex: Sex, type: String, key: String, color: int = ComponentColor.Default):
	var resolved_key := _split_lot_key(key)
	if resolved_key.is_empty():
		return

	resolved_key[0].unresolve(sex, type, resolved_key[1], color)

## Resolves a base body texture. This is done by the default resolver.
func resolve_body(sex: Sex, color: BodyColor):
	return _default_resolver.resolve_body(sex, color)

## Releases a previous successful body resolve. This is done by the
## default resolver.
func unresolve_body(sex: Sex, color: BodyColor):
	return _default_resolver.unresolve_body(sex, color)
