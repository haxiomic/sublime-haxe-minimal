import python.lib.io.FileIO;

using StringTools;
using Lambda;

class HaxeView extends sublime_plugin.ViewEventListener {

	static inline var HAXE_STATUS = 'haxe_status';

	override function on_modified() {
	}

	override function on_close() {
	}

	override function on_post_save_async() {
	}

	override function on_query_completions(prefix:String, locations:Array<Int>):Null<haxe.extern.EitherType<Array<Any>, python.Tuple<Any>>> {
		var hxml = HaxeProject.getHxmlForView(view);

		if (hxml == null) {
			view.set_status(HAXE_STATUS, 'Autocomplete: Could not find hxml');
			return null;
		}

		var viewContent = view.substr(new sublime.Region(0, view.size()));
		var haxeServer = HaxeProject.getHaxeServerHandle(view, Stdio);

		var location = locations[0];

		var completionMode: HaxeServer.CompletionMode = Unset;
		var fieldCompletion = false;

		// if we're in the middle of typing out a field, we should step back to the .
		var proceedingNonWordChar = viewContent.charAt(location - prefix.length - 1);
		switch proceedingNonWordChar {
			case '.':
				completionMode = Unset; // used for field completion
				fieldCompletion = true;
				location -= prefix.length;
			default:
				completionMode = Toplevel;
		}

		var result = haxeServer.display(hxml, view.file_name(), location, completionMode, completionMode == Unset, viewContent);

		if (!result.hasError) {
			/*
				# Parse completion XML
				Fields and type paths:
					<list>
						<i n="{name}" ?k="{field kind}">
							<t>?{type name}</t>
							<d>?{documentation}</d>
						</i>
						<i>...</i>
					</list>

				Top-level:
					<il>
						<i k="{kind}" ?t="{type}" ?p="{path}">
							{name}
						</i>
						<i>...</i>
					</il>
			*/

			var xml: Xml;
			try xml = Xml.parse(result.output)
			catch(e: Any) {
				view.set_status(HAXE_STATUS, 'Autocomplete: ' + result.output);
				return null;
			}

			var x = new haxe.xml.Fast(xml);

			var maxDisplayLength = 50;
			var overflowSuffix = ' …  ';

			var completions = new Array<{display: String, info: String, completion: String}>();

			if (x.hasNode.list) {

				for (item in x.node.list.nodes.i) {
					var name = item.att.n;
					var kind = item.has.k ? item.att.k : '';// var or method
					var type = item.hasNode.t ? item.node.t.innerData : '';

					// defaults
					var display = name;
					var info = type != '' ? type : (isUpperCase(name.charAt(0)) ? 'class' : 'module');
					var completion = name;
					
					switch kind {
						case 'method':
							// process for readability
							var c = generateFunctionCompletion(name, parseFunctionSignature(type));
							display = c.display;
							info = c.info;
							completion = c.completion;
					}

					completions.push({
						display: display,
						info: info,
						completion: completion
					});
				}

			} else if (x.hasNode.il) {

				for (item in x.node.il.nodes.i) {
					var name = item.innerData;
					var kind = item.att.k;
					var type = item.has.t ? item.att.t : null;
					var path = item.has.p ? item.att.p : null;

					var display = name;
					var info = type != null ? type : kind;
					var completion = name;

					// check if type represents a function, if so, process for readability
					if (type != null) {
						var t = parseFunctionSignature(type);
						if (t.parameters.length > 0) {
							var c = generateFunctionCompletion(name, parseFunctionSignature(type));
							display = c.display;
							info = c.info;
							completion = c.completion;
						}
					}

					completions.push({
						display: display,
						info: info,
						completion: completion
					});
				}

			}

			var sublimeCompletions = completions.map(function(c) {
				if (c.info == 'Unknown<0>') c.info = '•';

				if (c.display.length > (maxDisplayLength - overflowSuffix.length)) {
					c.display = c.display.substr(0, (maxDisplayLength - overflowSuffix.length)) + overflowSuffix;
				}
				return [
					c.display + 
					(c.info != null ? '\t' + c.info : ''),
					c.completion
				];
			});

			view.erase_status(HAXE_STATUS);
			
			return untyped python.Tuple.Tuple2.make(
				sublimeCompletions,
				sublime.Sublime.INHIBIT_WORD_COMPLETIONS /*| sublime.Sublime.INHIBIT_EXPLICIT_COMPLETIONS*/
			);

		} else {
			view.set_status(HAXE_STATUS, 'Autocomplete: ' + result.output);
			updateErrors(result.output);
		}

		return untyped python.Tuple.Tuple2.make(
			[],
			// inhibit all if it's in field completion mode
			fieldCompletion ? (sublime.Sublime.INHIBIT_WORD_COMPLETIONS | sublime.Sublime.INHIBIT_EXPLICIT_COMPLETIONS) : 0
		);
	}

	static function is_applicable(settings: sublime.Settings) {
		return settings.get('syntax') == 'Packages/Haxe Minimal/syntax/haxe.tmLanguage';
	}

	static function applies_to_primary_view_only() return false;

	static function updateErrors(haxeErrorString: String) {
		// @! todo display errors
	}

	static inline function generateFunctionCompletion(name: String, func: {
		parameters: Array<{name: String, type: String}>,
		returnType: String,
	}) {
		// remove first element if it is void
		if (func.parameters[0].type == 'Void') {
			func.parameters.shift();
		}

		// format parameters
		var parametersFormatted = func.parameters.map(function(p) return '${p.name}: ${p.type}').join(', ');

		var info = func.returnType;
		var display = func.parameters.length > 0 ? '$name( $parametersFormatted )' : '$name()';

		var i = 1;
		var snippetArguments = func.parameters.map(
			function(p) {
				var nameString = p.name != null ? ':${p.name}' : '';
				return "${" + i++ + nameString + "}";
			}
		);

		var completion = '$name(' + snippetArguments.join(', ') + ')';

		return {
			info: info,
			display: display,
			completion: completion
		}
	}

	/**
		Split function into parameters and return type

		This method does not validate the signature string
	**/
	static function parseFunctionSignature(signature: String) {
		// Examples
		// 	f : (Int -> ( Void -> String ) ) -> name : Int -> Array<String> -> Void
		// 	a : Array<Void->Void> -> Void
		// 	m : { x: String -> Int } -> Void

		var parameters = new Array<{name: String, type: String}>();
		var returnType: String = null;

		var arrowMarker = String.fromCharCode(0x1);

		// to make parsing easier, we replace the arrows with a single special character
		signature = signature.replace('->', arrowMarker);

		// split by -> only when outside parentheses
		var parts = new Array<String>();

		var i = 0;
		var buffer = '';
		var level = 0;
		for (i in 0...signature.length) {
			var c = signature.charAt(i);
			switch c {
				case '(', '<', '{': level++;
				case ')', '>', '}': level--;
				case c if (c == arrowMarker): 
					if (level <= 0) {
						// flush buffer
						parts.push(buffer.trim());
						buffer = '';
					} else {
						// restore arrow
						buffer += '->';
					}
				default: buffer += c;
			}
		}

		for(part in parts) {
			var firstColonIdx = part.indexOf(':');
			parameters.push({
				name: firstColonIdx != -1 ? part.substr(0, firstColonIdx).trim() : null,
				type: part.substr(firstColonIdx + 1).trim()
			});
		}

		returnType = buffer.trim();

		return {
			parameters: parameters,
			returnType: returnType
		}
	}

	static inline function isUpperCase(str: String) {
		return str.toUpperCase() == str;
	}

	static inline function clampString(str: String, minLength: Int, maxLength: Int, overflowSuffix, pad: String -> Int -> String) {
		if (str.length > maxLength - overflowSuffix.length) {
			str = str.substr(0, maxLength - overflowSuffix.length) + overflowSuffix;
		} else if (str.length < minLength) {
			str = pad(str, minLength);
		}
		return str;
	}

}