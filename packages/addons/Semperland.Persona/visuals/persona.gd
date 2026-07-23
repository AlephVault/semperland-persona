extends AlephVault__WindRose__REFMAP.Contrib.Citizens.Visuals.Citizen
## This is the same as a citizen visual, except that the resolution of
## a component using "1/" strips that prefix.

const _DefaultResolver = AlephVault__WindRose__REFMAP.Utils.DefaultResolver
const _LotDownloader = Semperland__Persona.Utils.LotDownloader

## Use this property to set a Persona-wide lot downloader.
## Useful to resolve and download new lots dynamically.
static var lot_downloader: _LotDownloader = null

static func _is_default_resolver() -> bool:
	var resolver_obj = AlephVault__WindRose__REFMAP.Visuals.People.resolver
	return resolver_obj is _DefaultResolver and is_instance_valid(resolver_obj)

func _resolve_component_layer(type: String, value, color: int = ComponentColor.Default) -> ResolvedLayer:
	if value is String and _is_default_resolver():
		value = value.strip_edges()
		if value.begins_with("1/"):
			value = value.substr(2)
	return super._resolve_component_layer(type, value, color)

func _refresh_visual_now(generation: int, chunked: bool) -> void:
	if lot_downloader != null:
		var again: Callable = func(): await _refresh_visual_now(generation, chunked)
		var lots := _lot_keys_from_traits()
		if not lots.is_empty() and await lot_downloader.download_lots(lots, again):
			return
	await super._refresh_visual_now(generation, chunked)

func _lot_keys_from_traits() -> Array[int]:
	var lots: Dictionary = {}
	for property in _get_traits_properties():
		var value = get(String(property))
		if not (value is String):
			continue
		var lot := _lot_key_from_value(value)
		if lot >= 2:
			lots[lot] = true

	var result: Array[int] = []
	for lot in lots.keys():
		result.append(int(lot))
	return result

func _lot_key_from_value(value: String) -> int:
	var key := value.strip_edges()
	var separator := key.find("/")
	if separator <= 0 or separator == key.length() - 1:
		return 0

	var lot_key := key.substr(0, separator)
	if not lot_key.is_valid_int():
		return 0

	var lot := lot_key.to_int()
	return lot if lot >= 2 else 0
