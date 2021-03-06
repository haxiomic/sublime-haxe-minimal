@:enum abstract EntryKind(Int) {
	var Unknown = 0;
	var Method = 1;
	var Var = 2;
	var Type = 3;
	var Package = 4;
}

class HaxeView extends sublime_plugin.ViewEventListener {

	static inline var HAXE_STATUS = 'haxe_status';


	static function is_applicable(settings: sublime.Settings) {
		return settings.get('syntax') == 'Packages/Haxe Minimal/syntax/haxe.tmLanguage';
	}

	static function applies_to_primary_view_only() return false;

	override function on_modified() {
	}

	override function on_close() {
	}

	override function on_post_save_async() {
	}

	override function on_query_completions(prefix:String, locations:Array<Int>):Null<haxe.extern.EitherType<Array<Any>, python.Tuple<Any>>> {
		var completionLocation = locations[0];
		var completionScope = view.scope_name(completionLocation);

		// handle autocomplete in specific scopes
		if (view.score_selector(completionLocation, "comment") > 0) {
			// comment scope should use default autocomplete
			return null;
		}

		var viewContent = view.substr(new sublime.Region(0, view.size()));

		// determine completion mode
		var displayMode: HaxeServer.DisplayMode = null;

		var proceedingNonWordChar = viewContent.charAt(completionLocation - prefix.length - 1);
		switch proceedingNonWordChar {
			case '.':
				displayMode = Field; // used for field completion
				// if we're in the middle of typing out a field, we should step back to the .
				completionLocation -= prefix.length;
			default:
				displayMode = Toplevel;
		}

		trace('Autocomplete scope "$completionScope" mode "$displayMode"');

		if (displayMode == null) return null;

		var hxml = HaxeProject.getHxmlForView(view);

		if (hxml == null) {
			view.set_status(HAXE_STATUS, 'Autocomplete: Could not find hxml');
			return null;
		}

		var haxeServer = HaxeProject.getHaxeServerHandle(view, Stdio);
		var result = haxeServer.display(hxml, view.file_name(), completionLocation, displayMode, displayMode == Field, viewContent);

		if (!result.hasError) {
			/*
				Completion XML

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
			try xml = Xml.parse(result.message)
			catch(e: Any) {
				view.set_status(HAXE_STATUS, 'Autocomplete: ' + result.message);
				return null;
			}

			var x = new haxe.xml.Access(xml);

			var maxDisplayLength = 50;
			var overflowSuffix = ' …  ';

			var completions = new Array<{display: String, info: String, completion: String, kind: EntryKind}>();

			if (x.hasNode.list) {
				for (item in x.node.list.nodes.i) {
					var name = item.att.n;
					var kind = item.has.k ? item.att.k : '';// var, method, type
					var type = item.hasNode.t ? item.node.t.innerData : '';

					// defaults
					var display = name;
					var info = switch kind {
						case 'var', 'method': type;
						default: kind;
					};
					var completion = name;

					switch kind {
						case 'method':
							// process for readability
							var c = generateFunctionCompletion(name, SyntaxTools.parseHaxeFunctionSignature(type));
							display = c.display;
							info = c.info;
							completion = c.completion;
					}

					completions.push({
						display: display,
						info: info,
						completion: completion,
						kind: switch kind {
							case 'var': Var;
							case 'method': Method;
							case 'type': Type;
							case 'package': Package;
							default: Unknown;
						}
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
						var t = SyntaxTools.parseHaxeFunctionSignature(type);
						if (t.parameters.length > 0) { // method type
							kind = 'method';
							var c = generateFunctionCompletion(name, t);
							display = c.display;
							info = c.info;
							completion = c.completion;
						} else {
							kind = 'var';
						}
					}

					completions.push({
						display: display,
						info: info,
						completion: completion,
						kind: switch kind {
							case null: Unknown;
							case 'var': Var;
							case 'method': Method;
							case 'type': Type;
							case 'package': Package;
							default: Unknown;
						}
					});
				}
			}

			var sublimeCompletions = completions.map(function(c) {
				// replace Unknown with • to reduce clutter
				if (c.info == 'Unknown<0>' || c.info == 'Unknown0') c.info = '•';
				// add kind prefix
				c.display = (switch c.kind {
					case Unknown: ' ';
					case Method: 'ƒ';//𝖿𝘍ƒ𝑓
					case Var: 'ᵥ';//𝘷𝘝ᵥ
					case Type: 'ᴛ';//ᴛ
					case Package: '.';
				}) + ' ' + c.display;
				// clamp string length
				if (c.display.length > (maxDisplayLength - overflowSuffix.length)) {
					c.display = c.display.substr(0, (maxDisplayLength - overflowSuffix.length)) + overflowSuffix;
				}
				// convert to sublime completion format
				return [
					c.display + 
					(c.info != null ? '\t' + c.info : ''),
					c.completion
				];
			});

			view.erase_status(HAXE_STATUS);
			
			return untyped python.Tuple.Tuple2.make(
				sublimeCompletions,
				sublimeCompletions.length > 0 ? sublime.Sublime.INHIBIT_WORD_COMPLETIONS : 0 // only inhibit word completions if we have haxe completions
			);

		} else {
			view.set_status(HAXE_STATUS, 'Autocomplete: ' + result.message);
			updateErrors(result.message);
		}

		// inhibit all if it's in field completion mode
		if (displayMode == Field) {
			return untyped python.Tuple.Tuple2.make([], sublime.Sublime.INHIBIT_WORD_COMPLETIONS | sublime.Sublime.INHIBIT_EXPLICIT_COMPLETIONS);
		} else {
			return null;
		}
	}

	override function on_hover(point: Int, hover_zone: Int) {
		if (hover_zone != sublime.Sublime.HOVER_TEXT) return;
		var scope = view.scope_name(point);

		var hxml = HaxeProject.getHxmlForView(view);

		if (hxml == null) {
			view.set_status(HAXE_STATUS, 'Autocomplete: Could not find hxml');
			return;
		}

		var viewContent = view.substr(new sublime.Region(0, view.size()));
		var haxeServer = HaxeProject.getHaxeServerHandle(view, Stdio);

		var displayMode: HaxeServer.DisplayMode = Type;

		var details = true;
		var result = haxeServer.display(hxml, view.file_name(), point, displayMode, details, viewContent);

		trace('on_hover "$scope" $result');

		try if (!result.hasError) {
			var x = new haxe.xml.Access(Xml.parse(result.message));
			// expecting <type>, however I've received <list> in the past

			var typeNode = x.node.type;
			var docs = typeNode.has.d ? typeNode.att.d : null;
			var type = typeNode.innerHTML;

			docs = docs != null ? '<p>' + docs.trim().replace('\n', '<br>') + '</p>' : '';

			view.show_popup('<code>$type</code>$docs', sublime.Sublime.HIDE_ON_MOUSE_MOVE_AWAY | sublime.Sublime.COOPERATE_WITH_AUTO_COMPLETE, untyped point, 700);
		} catch (e: Any) {
			trace('on_hover error: $e');
		}

	}

	static function updateErrors(haxeErrorString: String) {
		// @! todo display errors
	}

	static inline function generateFunctionCompletion(name: String, func: {
		parameters: Array<{name: String, type: String}>,
		returnType: String,
		optional: Bool,
	}) {
		// remove first element if it is void
		if (func.parameters[0] != null && func.parameters[0].type == 'Void') {
			func.parameters.shift();
		}

		// format parameters
		var parametersFormatted = func.parameters.map(function(p) return '${p.name}:${p.type}').join(', ');

		var info = func.returnType;
		var display = '${func.optional ? '?' : ''}$name($parametersFormatted)';

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