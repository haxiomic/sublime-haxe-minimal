import sys.io.Process;

@:enum
abstract HaxeExitCode(Int) from Int {
	var Success = 0;
	var CompileError = 1;
	var OtherError = 2;
}

enum ErrorRange {
	Lines(start:Int, end:Int);
	Characters(line: Int, offset: Int, length: Int);
}

class Compiler {

	static public function buildOnServer(
		args: Array<String>,
		compilationServerPort:Int,
		fallbackCompile: Bool = true,
		?onComplete: String -> String -> Void,
		?onError: Int -> String -> Void
	){
		// could also use net sockets to connect to the compilation server
		CompilerServer.touchServer(
			6000,
			function() build(args.concat(['--connect', '$compilationServerPort']), onComplete, onError),
			function(errorMessage) {
				// server is down
				if (fallbackCompile) {
					if (onError != null) onError(2, errorMessage);
				} else {
					build(args, onComplete, onError);
				}
			}
		);
	}

	static public function build(
		args: Array<String>,
		?onComplete: String -> String -> Void,
		?onError: Int -> String -> Void
	) {
		var process = new Process('haxe', args);
		var exitCode = process.exitCode(true);
		var stdout = process.stdout.readAll().toString();
		
		process.close();

		if (exitCode != 0) {
			var stderr = process.stderr.readAll().toString();
			if (onError != null) onError(exitCode, stderr);
		} else {
			var stderr = process.stderr.readAll().toString();
			var stdout = process.stdout.readAll().toString();
			if (onComplete != null) onComplete(stdout, stderr);
		}
	}

	static public function parseCompilerOutput(compilerOutput: String) {
		// filepath/filename.hx:42: characters 3-9 : Missing ;
		var errorPositionPattern = ~/^([^:\n]+):(\d+):([\w\d\s-]+:)?\s*(.*)$/gm;

		// see get_error_pos in syntax/lexer.ml in haxe source 
		var singleCharPattern = ~/character (\d+)/i;
		var charRangePattern = ~/characters (\d+)-(\d+)/i;
		var lineRangePattern = ~/lines (\d+)-(\d+)/i;

		var errors = new Array<{
			filePath: String,
			error: String,
			range: ErrorRange
		}>();

		errorPositionPattern.map(compilerOutput, function(ereg) {
			var filePath = errorPositionPattern.matched(1);
			var lineNumber = Std.parseInt(errorPositionPattern.matched(2));
			var rangeString = errorPositionPattern.matched(3); // may be null
			var error = errorPositionPattern.matched(4);

			var errorRange: ErrorRange = Lines(lineNumber, lineNumber);

			// adjust the error range if we have a range string in the error
			if (rangeString != null) {
				// character positions are from the start of the line
				// where 1 = first character in line
				if (singleCharPattern.match(rangeString)) {
					var characterPosition = Std.parseInt(singleCharPattern.matched(1));
					errorRange = Characters(lineNumber, (characterPosition - 1), 1);
				} else
				if(charRangePattern.match(rangeString)) {
					var characterPositionStart = Std.parseInt(charRangePattern.matched(1));
					var characterPositionEnd = Std.parseInt(charRangePattern.matched(2));
					var length = characterPositionEnd - characterPositionStart;
					errorRange = Characters(lineNumber, (characterPositionStart - 1), length);
				} else
				if(lineRangePattern.match(rangeString)) {
					var lineStart = Std.parseInt(lineRangePattern.matched(1));
					var lineEnd = Std.parseInt(lineRangePattern.matched(2));
					errorRange = Lines(lineStart, lineEnd);
				}
			}

			errors.push({
				filePath: filePath,
				error: error,
				range: errorRange
			});

			return '';
		});
	}

}