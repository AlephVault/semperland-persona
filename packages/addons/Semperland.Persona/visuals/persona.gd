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
