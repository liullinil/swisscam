class_name WebFiles
extends RefCounted

## Открытие и сохранение файлов в браузере.
##
## В вебе обычного файлового диалога у движка нет: страница должна сама создать
## <input type="file">, причём обязательно в ответ на действие пользователя,
## иначе браузер откажется его показывать. Поэтому выбор файлов идёт через
## маленькую вставку на JavaScript, а обратно приходит JSON с именами и текстом.

const PICK_JS := """
window.swisscamPick = function(cb) {
	var input = document.createElement('input');
	input.type = 'file';
	input.multiple = true;
	input.accept = '.nc,.txt,.cnc,.prg,.mpf,.gcode';
	input.style.display = 'none';
	document.body.appendChild(input);
	input.onchange = function() {
		var files = Array.prototype.slice.call(input.files);
		Promise.all(files.map(function(f) {
			return f.text().then(function(t) { return [f.name, t]; });
		})).then(function(pairs) {
			document.body.removeChild(input);
			cb(JSON.stringify(pairs));
		});
	};
	input.click();
};
"""

## Колбэк нужно держать живым, пока пользователь возится с диалогом.
static var _callback: JavaScriptObject


static func available() -> bool:
	return OS.has_feature("web")


## handler получает Array[Dictionary] вида {name, text}.
static func pick_text_files(handler: Callable) -> void:
	if not available():
		return
	JavaScriptBridge.eval(PICK_JS, true)
	_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
		var out: Array = []
		if args.size() > 0:
			var parsed = JSON.parse_string(str(args[0]))
			if parsed is Array:
				for pair in parsed:
					if pair is Array and pair.size() >= 2:
						out.append({"name": str(pair[0]), "text": str(pair[1])})
		handler.call(out))
	var window := JavaScriptBridge.get_interface("window")
	if window == null:
		return
	window.swisscamPick(_callback)


## Отдаёт текст пользователю как файл — в браузере это единственный способ «сохранить».
static func download_text(file_name: String, text: String) -> void:
	if not available():
		return
	JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "text/plain")
