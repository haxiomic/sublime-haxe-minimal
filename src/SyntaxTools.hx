class SyntaxTools {
	
	/**
		A, B: (c, d), E -> ["A, " B: (c, d)", " E"]
	**/
	static public function scopeAwareSplit(
		string: String,
		delimiter: String,
		scopeIncreaseChars: String = '(<{',
		scopeDecreaseChars: String = ')>}'
	) {
		var parts = new Array<String>();
		var buffer = new StringBuf();
		var levels = [for (i in 0...scopeIncreaseChars.length) 0];

		for (i in 0...string.length) {
			var c = string.charAt(i);

			var groundLevel: Bool = true;
			for (l in levels) if (l > 0) {
				groundLevel = false;
				break;
			}

			if (c == delimiter && groundLevel) {
				// clear buffer
				parts.push(buffer.toString());
				buffer = new StringBuf();
			} else {
				var incIndex = scopeIncreaseChars.indexOf(c);
				var decIndex = scopeDecreaseChars.indexOf(c);

				if (incIndex != -1) {
					levels[incIndex]++;
				}
				if (decIndex != -1) {
					levels[decIndex]--;
				}

				buffer.add(c);
			}
		}

		parts.push(buffer.toString());
		return parts;
	}

	/**
		(string) -> string
	**/
	static public function unwrap(string: String, openChar: String, closeChar: String, recursive: Bool = false) {
		var level = 0;
		var buffer = new StringBuf();
		var matchingChars = openChar == closeChar;

		for (i in 0...string.length) {
			var c = string.charAt(i);

			if (matchingChars) {
				if (c == openChar)  level = level == 1 ? 0 : 1;
				if (level == 1)     buffer.add(c);
			} else {
				if (c == closeChar) level--;
				if (level >= 1)     buffer.add(c);
				if (c == openChar)  level++;
			}

		}

		var unwrapped = buffer.length == 0 ? string : buffer.toString();

		if (recursive) {
			if (unwrapped.length == string.length) {
				// string hasn't changed therefore unwrap is complete
				return string;
			} else {
				return unwrap(unwrapped, openChar, closeChar, recursive);
			}
		} else {
			return unwrapped;
		}
	}

	/**
		Split function into parameters and return type

		This method does not validate the signature string
	**/
	static public function parseHaxeFunctionSignature(signature: String) {
		var parameters: Array<{name: String, type: String}>;
		var returnType: String;

		var arrowMarker = '\x1F';
		var scopeInc = '(<{';
		var scopeDec = ')>}';

		// split by -> only when outside parentheses
		// to make parsing easier, we replace the arrows with a single special character
		var arrowParts = scopeAwareSplit(signature.replace('->', arrowMarker), arrowMarker, scopeInc, scopeDec);

		// return type is always the last arrow part
		returnType = arrowParts.pop().trim();

		if (arrowParts.length > 0) {
			// find argument strings
			var unwrappedArrowParts = arrowParts.map(part -> unwrap(part, '(', ')'));

			// the first arrow part must be handled specially because it may contain an argument list from the new syntax
			var parameterExpressions = scopeAwareSplit(unwrappedArrowParts[0], ',', scopeInc, scopeDec).concat(unwrappedArrowParts.slice(1));

			// restore any arrows at different scope levels
			parameterExpressions = parameterExpressions.map(p -> p.replace(arrowMarker, '->'));

			parameters = parameterExpressions.map(expr -> {
				// split expressions of the form "name: Type"
				var firstColonIdx = expr.indexOf(':');
				return {
					name: firstColonIdx != -1 ? expr.substr(0, firstColonIdx).trim() : null,
					type: expr.substr(firstColonIdx + 1).trim()
				};
			});
		} else {
			parameters = [];
		}


		return {
			parameters: parameters,
			returnType: returnType
		}
	}

}