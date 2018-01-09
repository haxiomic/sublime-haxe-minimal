# Todo
- What happens if a view changes syntax so it's no longer a haxe file?
	- Use scope rather than extension
- Function argument completion (see TypeScript plugin for good implementation)
- Support syntax highlighting and completion in string interpolation '${...}'
- Build and update errors as the file is changed but use more minimalistic error display
- Create an error console panel with clickable errors like it used to have
	- We can support colored output by setting the synax of the panel and using hidden characters – maybe best to use the colored ascii plugin's syntax file, maybe by making SublimeANSI a package dependency
- Should _always_ buildOnSave but not always produce output
- Enable auto-completion without a build.hxml file
- Run on save and show result in custom console. The following should work
	- New file (without save)
	- Quick class def (autocomplete should work)
	- execute haxe-build-run command
	- Custom panel shows build and run result (probably via neko or --interp)
- Better system to guess build.hxml – we should find all build.hxml files in a project and check if the view is involved in the compilation
- Allow build.hxml to be specified
- Fix weird indent:
	weird_indent({
		});
- Better clear errors
	- When a compile completes successfully, errors on views that were involved in the build should also be cleared
	- When a compile error occurs, all the views involved can be considered a compile-error group
	- If compilation occurs involving any one of those views we clear the errors for all the other views to be reevaluated
	- We need to make sure the compilation groups object doesn't keep growing for ever
	? If a view is closed it is removed from all groups
	- If a group has no groups it is removed
	* Split displayErrors into parseErrors and displayErrors, where parseErrors gives us our list of views affected by the compile
- Kill compilation server when unused or sublime exits
	- Kill it when the last open haxe view closes?
	- What about multiple windows with a haxe server
? Use a different haxe server port if 6000 is in use
- Show symbol usages via panel

# Notes
- Haxe supports determining all occurrences of a given type, field or variable in all compiled files
- It also supports 'goto definition' functionality which can help resolve ambiguity in sublime's built-in

# Haxe Bugs
- Python .exitCode(false) should be asynchronous but instead blocks the thread on long processes. This is because reading the stdout/stderr is a blocking operation. Solution is available here https://stackoverflow.com/questions/375427/non-blocking-read-on-a-subprocess-pipe-in-python
- Python missing mkstemp and others in python.lib.Tempfile
- Python missing fdopen
- https://api.haxe.org/python/lib/io/IOBase.html seek whence should be optional
- https://api.haxe.org/python/lib/io/IOBase.html truncate size should be optional
- Python BytesBuffer, bytesBuffer.length fails, as does messageBuffer.add(buffer.getBytes());
	- Seems to fail when calling bytesBuffer.getBytes() twice