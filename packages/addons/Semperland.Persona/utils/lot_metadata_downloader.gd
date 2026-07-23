extends Object
## Abstract downloader for Persona lot metadata.
##
## Implementations should override download_lot() and return dictionaries shaped
## as:
## - {"ok": true, "value": {"name": ..., "url": ...}}
## - {"ok": false, "error": ...}

## Downloads metadata for lot n.
##
## n must be a positive integer. Subclasses must return a dictionary with:
## - name: The lot display name.
## - url: The lot archive URL.
func download_lot(n: int) -> Dictionary:
	if n <= 0:
		return _failed("invalid_lot_id")
	return _failed("not_implemented")

func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value}

func _failed(error: Variant) -> Dictionary:
	return {"ok": false, "error": error}
