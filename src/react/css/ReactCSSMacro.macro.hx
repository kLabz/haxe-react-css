package react.css;

import haxe.EnumTools;
import haxe.crypto.Sha256;
import haxe.io.Path;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import sys.FileSystem;
import sys.io.File;

#if css_types import css.Properties; #end
import react.macro.ReactComponentMacro;
import react.macro.MacroUtil.extractMetaString;

using StringTools;

typedef CssModule = {
	var path:String;
	var hash:String;
	var className:String;
	var styles:String;
	var stylesPos:Position;
	var clsInjection:Map<String, Type>;
	var priority:Int;
}

class ReactCSSMacro {
	public static inline var BUILDER_KEY = 'REACT_CSS';

	public static var META_NAME = ':css';
	public static var PRIORITY_META_NAME = ':css.priority';

	public static var STYLES_FIELD = 'styles';
	public static var MEDIA_QUERIES_FIELD = 'mediaQueries';
	public static var CLASSNAME_FIELD = 'className';

	public static var BASE_DEFINE = 'react.css.base';
	public static var OUT_DEFINE = 'react.css.out';
	public static var SALT_DEFINE = 'react.css.salt';
	public static var SOURCEMAP_DEFINE = 'react.css.sourcemap';

	static var hasChanged:Bool = false;
	@:persistent static var lastBase:Null<String>;
	@:persistent static var thisModule:Null<String>;
	@:persistent static var cssModules:Map<String, CssModule>; // path as key

	public static function init():Void {
		hasChanged = false;

		// Register react component builder
		ReactComponentMacro.appendBuilder(builder, BUILDER_KEY);

		// Generate css _after_ JS -- this might be an issue with webpack/etc.?
		Context.onAfterGenerate(afterGenerate);
	}

	static function builder(cls:ClassType, fields:Array<Field>):Array<Field> {
		if (!cls.meta.has(META_NAME)) return fields;

		// Skip build during completion,
		// but hide `styles` field unless it has `@:keep` meta
		if (Context.defined('display')) {
			var foundStyles = false;
			var foundMediaQueries = false;

			for (f in fields) {
				switch (f.name) {
					case n if (n == STYLES_FIELD): foundStyles = true;
					case n if (n == MEDIA_QUERIES_FIELD): foundMediaQueries = true;
					case _: continue;
				}

				if (!Lambda.exists(f.meta, m -> m.name == ':keep')) {
					f.meta.push({
						name: ':noCompletion',
						pos: f.pos,
						params: []
					});
				}

				if (foundStyles && foundMediaQueries) break;
			}

			return fields;
		}

		var meta = cls.meta.get().filter(m -> m.name == META_NAME)[0];
		initPersistentData();

		hasChanged = true;
		var sourcemap = Context.defined(SOURCEMAP_DEFINE);
		var module = cls.module.split('.').pop();
		var path = cls.pack.concat([module, cls.name]).join('.');
		var hash = getHash(path);
		var className = '${cls.name}-${hash}';

		for (f in fields) {
			if (f.name == CLASSNAME_FIELD) {
				#if (haxe >= version("4.3.0"))
				Context.reportError('@:css needs to create a `$CLASSNAME_FIELD` field', meta.pos);
				Context.error('... But field is already declared here', f.pos);
				#else
				Context.error('@:css needs to create a `$CLASSNAME_FIELD` field, but it already exists', meta.pos);
				#end
			}
		}

		fields.push({
			name: CLASSNAME_FIELD,
			doc: "Generated CSS class name for this component",
			access: [AStatic, APublic, AFinal],
			kind: FVar(macro :String, macro $v{className}),
			pos: meta.pos
		});

		var stylesExpr = meta.params.length == 0 ? getCssField(fields) : meta.params[0];
		if (stylesExpr == null) {
			Context.error(
				'Cannot find CSS source\n' +
				'Either declare CSS inside this `@${META_NAME}` meta\n' +
				'Or add a `${STYLES_FIELD}` field of type `react.css.Stylesheet`',
				meta.pos
			);
		}

		var styles = extractStyles(stylesExpr);

		#if css_types
		var mediaQueriesExpr = meta.params.length == 0 ? getMediaQueries(fields) : null;
		if (mediaQueriesExpr != null) styles += extractMediaQueries(mediaQueriesExpr);
		#end

		// Inject own class
		styles = ~/(^|[^\w])_([^\w])/g.replace(styles, '$1.$className$2');

		// Prepare injection of other components' classNames
		var clsInjection = new Map<String, Type>();
		styles = ~/\$([a-zA-Z0-9_]+)/g.map(styles, function(r:EReg) {
			var ident = r.matched(1);
			try {
				var type = Context.resolveType(TPath({pack: [], name: ident}), Context.currentPos());
				switch (type) {
					case TInst(_, _): clsInjection.set(ident, type);

					case _:
						// TODO: catch it earlier while we still have good positions
						Context.error(
							'React CSS: `$$Ident` notation is only allowed for components',
							stylesExpr.pos
						);
				}
			} catch (e) {
				// TODO: catch it earlier while we still have good positions
				Context.error('Cannot resolve component `$ident`', stylesExpr.pos);
			}
			return r.matched(0);
		});

		// Retype when this macro changes
		Context.registerModuleDependency(Context.getLocalModule(), thisModule);

		// TODO: store informations for source map if enabled
		cssModules.set(path, {
			path: path,
			hash: hash,
			className: className,
			styles: styles,
			stylesPos: stylesExpr.pos,
			clsInjection: clsInjection,
			priority: !cls.meta.has(PRIORITY_META_NAME) ? 1 : {
				var meta = cls.meta.get().filter(m -> m.name == PRIORITY_META_NAME)[0];
				var val = ExprTools.getValue(meta.params[0]);
				if (Std.isOfType(val, Int)) val;
				else Std.parseInt(Std.string(val));
			}
		});

		return fields;
	}

	static function initPersistentData():Void {
		if (cssModules == null) cssModules = [];

		if (thisModule == null) {
			var thisPath = Context.resolvePath('react/css/ReactCSSMacro.macro.hx');
			thisModule = FileSystem.fullPath(thisPath);
		}
	}

	static function getHash(path:String):String {
		var key = path;
		if (Context.defined(SALT_DEFINE)) key = Context.definedValue(SALT_DEFINE) + key;
		var hash = Sha256.encode(key).substr(0, 6);
		if (cssModules.exists(hash)) return getHash(path + '_');
		return hash;
	}

	#if css_types
	static function getCssField(fields:Array<Field>):Null<Expr> {
		for (f in fields) {
			if (f.name != STYLES_FIELD) continue;

			// Force dce of field unless `@:keep`
			if (!Lambda.exists(f.meta, m -> m.name == ':keep')) fields.remove(f);

			switch (f.kind) {
				case FVar(TPath({name: "Dynamic", params: [TPType(TPath({name: "Properties"}))]}), expr):
					return expr;

				case FVar(TPath({name: "Stylesheet", params: []}), expr):
					return expr;

				case FVar(null, expr):
					Context.typeExpr(macro @:pos(expr.pos) ($expr :Dynamic<css.Properties>));
					return expr;

				case _:
					Context.error('React CSS expects `${STYLES_FIELD}` field to be of `react.css.Stylesheet` type', f.pos);
			}

			trace(f.kind);
		}

		return null;
	}

	static function getMediaQueries(fields:Array<Field>):Null<Expr> {
		for (f in fields) {
			if (f.name != MEDIA_QUERIES_FIELD) continue;

			// Force dce of field unless `@:keep`
			if (!Lambda.exists(f.meta, m -> m.name == ':keep')) fields.remove(f);

			switch (f.kind) {
				case FVar(TPath({name: "Dynamic", params: [TPType(
					TPath({name: "Dynamic", params: [TPType(TPath({name: "Properties"}))]})
				)]}), expr):
					return expr;

				case FVar(TPath({name: "Dynamic", params: [TPType(TPath({name: "Stylesheet", params: []}))]}), expr):
					return expr;

				case FVar(null, expr):
					Context.typeExpr(macro @:pos(expr.pos) ($expr :Dynamic<Dynamic<css.Properties>>));
					return expr;

				case _:
					Context.error('React CSS expects `${MEDIA_QUERIES_FIELD}` field to be of `Dynamic<react.css.Stylesheet>` type', f.pos);
			}

			trace(f.kind);
		}

		return null;
	}
	#else
	static function getCssField(fields:Array<Field>):Null<Expr> return null;
	static function getMediaQueries(fields:Array<Field>):Null<Expr> return null;
	#end

	static function extractStyles(expr:Expr):String {
		return switch (expr.expr) {
			case EConst(CString(str)) if (str.indexOf('\n') > -1):
				str;

			case EConst(CString(str)):
				// TODO: better detect inline css to avoid unneeded fs checks
				var extContent = getRelativeFileContent(str, true, expr.pos);
				extContent == null ? str : extContent;

			case EField(_, _):
				var path = ExprTools.toString(expr);
				getRelativeFileContent(path, expr.pos);

			#if css_types
			case EObjectDecl(fields):
				var ret = new StringBuf();

				for (f in fields) {
					var buf = new StringBuf();

					switch (f.expr.expr) {
						case EObjectDecl(properties):
							for (f in properties) {
								var prop = f.field;
								buf.add('\t');
								buf.add(PropertiesHelper.hyphenize(prop));
								buf.add(': ');

								var t:Type;

								if (f.quotes.match(Quoted)) {
									// Skip checks when field is quoted
									t = ComplexTypeTools.toType(macro :css.Properties.CSSNumberOrArray);
								} else {
									// Check for extra fields, make sure typing fits
									t = Context.typeof(macro @:pos(f.expr.pos) {
										var p:css.Properties = {};
										var prop = p.$prop;
										// Note: currently triggers https://github.com/kLabz/haxe-react-css/issues/2
										prop = ${f.expr};
										prop;
									});
								}

								renderValue(buf, f.expr, t, true);

								buf.add(';\n');
							}

						case EBlock([]):
							// Empty object

						case _:
							trace(f.expr.expr);
							Context.error('Invalid value', f.expr.pos);
					}

					if (buf.length > 0) {
						ret.add(trimLines(f.field));
						ret.add(' {\n');
						ret.add(buf.toString());
						ret.add('}\n');
					}
				}

				ret.toString();
			#end

			case EBlock([]):
				// Empty object
				"";

			case _:
				trace(expr);
				Context.error('Cannot parse css source', expr.pos);
		};
	}

	static function renderValue(
		buf:StringBuf,
		expr:Expr,
		expectedType:Type,
		?topLevel:Bool = false
	):Void {
		switch (expr) {
			case macro $i{i}:
				var found = extractEnumAbstractValue(expectedType, i, buf, expr.pos);

				if (!found) {
					var t = ComplexTypeTools.toType(macro :css.GlobalValue);
					found = extractEnumAbstractValue(t, i, buf, expr.pos);

					if (!found) {
						Context.error(
							'React CSS cannot resolve identifiers (yet)\n'
							+ 'See https://github.com/kLabz/haxe-react-css/issues/2',
							expr.pos
						);
					}
				}

			case (macro $i{ab}.$i) | (macro css.$ab.$i):
				var found = extractEnumAbstractValue(expectedType, i, ab, buf, expr.pos);

				if (!found) {
					var t = try ComplexTypeTools.toType(macro :css.$ab) catch (_) null;
					if (t != null) {
						found = extractEnumAbstractValue(t, i, buf, expr.pos);
					}

					if (!found) {
						Context.error(
							'React CSS cannot resolve identifiers (yet)\n'
							+ 'See https://github.com/kLabz/haxe-react-css/issues/2',
							expr.pos
						);
					}
				}

			case {expr: EConst(_)}:
				var val = ExprTools.getValue(expr);
				addConstValue(buf, val, expectedType, expr.pos);

			case (macro Var($v{(s:String)})) | (macro Var($i{s})):
				while (!s.startsWith('--')) s = '-' + s;
				buf.add('var($s)');

			case macro Important($e{e}) if (topLevel):
				renderValue(buf, e, expectedType, false);
				buf.add(' !important');

			case macro $a{items}: // EArrayDecl(items):
				var values:Array<String> = [];
				for (i in items) {
					values.push({
						var val = ExprTools.getValue(i);
						resolveCSSLength(val);
					});
				}

				buf.add(values.join(' '));

			case _:
				try {
					var val = ExprTools.getValue(expr);
					// TODO: can't be an array?
					addConstValue(buf, val, expectedType, expr.pos);
				} catch (e) {
					trace(e);
					Context.error('React CSS: unsupported expression', expr.pos);
				}
		}
	}

	#if css_types
	static function extractMediaQueries(expr:Expr):String {
		return switch (expr.expr) {
			case EObjectDecl(fields):
				var buf = new StringBuf();

				for (f in fields) {
					buf.add('@media (${f.field}) {\n');
					buf.add(extractStyles(f.expr));
					buf.add('}\n');
				}

				buf.toString();

			case EBlock([]):
				// Empty object
				"";

			case _:
				trace(expr);
				Context.error('Cannot parse media queries css source', expr.pos);
		};
	}

	static function resolveCSSLength(val:Any):CSSLength {
		if (Std.isOfType(val, Int)) return (val :Int);
		else if (Std.isOfType(val, Float)) return (val :Float);
		else return (val :String);
	}

	static function resolveCSSNumber(val:Any):CSSNumber {
		if (Std.isOfType(val, Int)) return (val :Int);
		else if (Std.isOfType(val, Float)) return (val :Float);
		else return (val :String);
	}

	static function extractEnumAbstractValue(
		t:Type,
		ident:String,
		?abstractName:String,
		buf:StringBuf,
		pos:Position
	):Bool {
		switch (t) {
			case TAbstract(_, [TAbstract(_.get() => a, [])]) | TAbstract(_.get() => a, []):
				if (abstractName == null || abstractName == a.name) {
					for (v in a.impl.get().statics.get()) {
						if (v.name == ident) {
							switch Context.getTypedExpr(v.expr()).expr {
								case ECast(e, _):
									var val = ExprTools.getValue(e);
									buf.add(val);
									return true;

								case _:
									Context.error('Cannot extract value from this identifier', pos);
							}

							break;
						}
					}
				}

			case TAbstract(_.toString() => "Null", [TInst(_.toString() => "String", [])]):
				return false;

			case _:
				throw false;
		}

		return false;
	}

	static function addConstValue(buf:StringBuf, val:Any, t:Type, pos:Position):Void {
		val = maybeApplyStringInterp(val, pos);

		switch (t) {
			case TAbstract(_, [TAbstract(_.get() => a, [])]) | TAbstract(_.get() => a, []):
				switch (a.name) {
					case "CSSLengthOrArray":
						buf.add(resolveCSSLength(val));

					case "CSSNumberOrArray":
						buf.add(resolveCSSNumber(val));

					case "CSSLength":
						buf.add(resolveCSSLength(val));

					case "CSSNumber":
						buf.add(resolveCSSNumber(val));

					case _:
						buf.add(Std.string(val));
				}

			case TAbstract(_.toString() => "Null", [TInst(_.toString() => "String", [])]):
				buf.add(val);

			case _:
				// css.Properties currently only has fields of String or enum abstract type
				throw false;
		}
	}

	static function maybeApplyStringInterp(val:Any, pos:Position):Any {
		if (Std.isOfType(val, String)) {
			try {
				var e = haxe.macro.MacroStringTools.formatString(val, pos);
				// TODO: resolve identifiers somehow
				return ExprTools.getValue(e);
			} catch (_) {}
		}

		return val;

	}
	#end

	static function getRelativeFileContent(path:String, ?skipErrors:Bool, ?pos:Position):Null<String> {
		var base = Context.resolvePath(Context.getLocalModule().split('.').join('/') + '.hx');
		var p = Path.join([Path.directory(base), path]);

		if (FileSystem.exists(p)) {
			Context.registerModuleDependency(Context.getLocalModule(), p);
			return File.getContent(p);
		}

		if (skipErrors) return null;
		if (pos == null) pos = Context.currentPos();
		Context.error('Cannot find file $path', pos);
		return null;
	}

	static function afterGenerate():Void {
		if (!Context.defined(OUT_DEFINE)) return;

		var base = null;
		if (Context.defined(BASE_DEFINE)) {
			var basePath = Context.definedValue(BASE_DEFINE);
			if (FileSystem.exists(basePath) && !FileSystem.isDirectory(basePath)) {
				base = File.getContent(basePath);
			} else {
				throw '[React CSS] Cannot find base file $basePath';
			}
		}

		if (base != lastBase) hasChanged = true;
		lastBase = base;
		if (!hasChanged) return;

		var out = Context.definedValue(OUT_DEFINE);
		var sourcemap = Context.defined(SOURCEMAP_DEFINE);
		var buff = new StringBuf();

		// TODO: source map if enabled
		if (base != null) buff.add(base + '\n');

		if (cssModules != null) {
			// Apply priority levels to add control over overrides order
			// (higher priority = included later in final css file)
			var modules:Array<CssModule> = [for (mod in cssModules) mod];
			modules.sort((m1, m2) -> m1.priority - m2.priority);

			// TODO: source map if enabled
			for (mod in modules) {
				var styles = mod.styles;

				for (ident => type in mod.clsInjection) {
					switch (type) {
						case TInst(_.get() => cls, _):
							var module = cls.module.split('.').pop();
							var path = cls.pack.concat([module, cls.name]).join('.');
							var def = cssModules.get(path);

							if (def == null) {
								Context.error(
									'Cannot find className for component `${cls.name}`',
									mod.stylesPos
								);
							} else {
								styles = styles.replace("$" + ident, '.' + def.className);
							}

						case _: throw false;
					}
				}

				buff.add(styles + '\n');
			}
		}

		// TODO: source map if enabled
		// if (sourcemap) buff.add('/*# sourceMappingURL=${Context.definedValue(SOURCEMAP_DEFINE)} */\n');
		// trace(buff.toString());

		var dir = Path.directory(out);
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		File.saveContent(out, buff.toString());
	}

	static function trimLines(str:String):String {
		var lines = str.split("\n").map(StringTools.trim);

		// Remove leading empty lines
		while (lines.length > 0) {
			var line = lines[0];
			if (line != "") break;
			lines.shift();
		}

		// Remove trailing empty lines
		while (lines.length > 0) {
			var line = lines[lines.length - 1];
			if (line != "") break;
			lines.pop();
		}

		return lines.join("\n");
	}
}
