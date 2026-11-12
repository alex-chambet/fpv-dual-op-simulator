class_name UpdateCheck
extends Node
## Asks GitHub for the latest release and says so when it is newer than this build.
##
## It must never get in the way: the request is asynchronous, has a timeout, and any failure (no
## network, rate limit, odd answer) is silent - the player just sees no banner. It runs once per
## launch, not each time the home page is shown.

const API := "https://api.github.com/repos/alex-chambet/fpv-dual-op-simulator/releases/latest"
const TIMEOUT := 8.0

## "Version 2.1" or "v2.1" or "2.1.3" -> [2, 1, 3]; empty when there is no number in it.
static func parse(text: String) -> Array:
	var m := RegEx.create_from_string("(\\d+(?:\\.\\d+)*)").search(text)
	if m == null:
		return []
	var out := []
	for part in m.get_string(1).split("."):
		out.append(int(part))
	return out


## True when `latest` is strictly newer than `current` (missing parts count as 0: 2.1 == 2.1.0).
static func is_newer(latest: String, current: String) -> bool:
	var a := parse(latest)
	var b := parse(current)
	if a.is_empty() or b.is_empty():
		return false
	for i in maxi(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


static var _done := false
static var _result := {}   ## {tag, url} once a newer release is known, for later visits to the home page

## `on_newer(tag, url)` is called when a newer release exists. Once known, the answer is kept
## and given again straight away on later visits to the home page.
func check(current: String, on_newer: Callable) -> void:
	if not _result.is_empty():
		on_newer.call_deferred(_result.tag, _result.url)
		return
	if _done:
		return
	_done = true
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			return
		var tag := str(data.get("tag_name", ""))
		var url := str(data.get("html_url", ""))
		if tag != "" and url.begins_with("https://github.com/") and is_newer(tag, current):
			_result = {"tag": tag, "url": url}
			on_newer.call_deferred(tag, url))
	if http.request(API, PackedStringArray(["User-Agent: fpv-dualop", "Accept: application/vnd.github+json"])) != OK:
		http.queue_free()
