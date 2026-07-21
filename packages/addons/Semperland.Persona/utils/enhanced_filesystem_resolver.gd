extends AlephVault__WindRose__REFMAP.Utils.Resolver

const _DefaultResolver = AlephVault__WindRose__REFMAP.Utils.DefaultResolver
const _FileSystemResolver = AlephVault__WindRose__REFMAP.Utils.FileSystemResolver

const DEFAULT_URL: String = "local://default"

var _resolvers: Dictionary = {}
var _default_resolver: _DefaultResolver = null
var _lots: Dictionary = {}

func _init():
	_default_resolver = _DefaultResolver.new()
	_resolvers[DEFAULT_URL] = _default_resolver
	_lots[1] = DEFAULT_URL

## Registers a lot, which is an index against one of the registered
## root directories and resolvers. Using lots will take place later,
## related to the intended component keys. Many lots can refer to
## the same root path.
func add_lot(n: int, root_directory: String) -> bool:
	if n <= 1 or _lots.has(n) or or not _resolver.has(root_directory):
		return false
	_lots[n] = root_directory
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

## Resolves a non-body component texture. Implementations should
## return Texture2D or null. Callers ignore non-Texture2D values
## and textures whose dimensions are not 128x192.
func resolve(sex: Sex, type: String, key: String, color: int = ComponentColor.Default):
	pass

## Releases a previous successful non-body resolve. If the key comes
## like "{idx}_{color}", this will be handled from the default resolver,
## same as using "1/{idx}_{color}". If the key comes like "{N}/{idx}_{color}"
## but N is not a positive number registered here as a "lot index", then
## nothing will be done. Otherwise, the "{N}/" prefix will be stripped and
## the remaining part will be passed to the resolver associated to the lot
## entry registered as N. Then, un-resolution will take place.
func unresolve(sex: Sex, type: String, key: String, color: int = ComponentColor.Default):
	pass

## Resolves a base body texture. This is done by the default resolver.
func resolve_body(sex: Sex, color: BodyColor):
	return _default_resolver.resolve_body(sex, color)

## Releases a previous successful body resolve. This is done by the
## default resolver.
func unresolve_body(sex: Sex, color: BodyColor):
	return _default_resolver.unresolve_body(sex, color)
