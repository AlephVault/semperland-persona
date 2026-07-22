extends AlephVault__WindRose__REFMAP.Contrib.Citizens.Entities.Navigability
## REFMAP citizen entity using Persona visual resolution.

const _PersonaVisual = Semperland__Persona.Visuals.Persona

func _create_visual() -> AlephVault__WindRose__REFMAP.Contrib.Citizens.Visuals.Citizen:
	return _PersonaVisual.new()
