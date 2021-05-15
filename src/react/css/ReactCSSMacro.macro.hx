package react.css;

import haxe.macro.ExprTools;
import haxe.crypto.Sha256;
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import sys.FileSystem;
import sys.io.File;

import react.macro.ReactComponentMacro;
import react.macro.MacroUtil.extractMetaString;

using StringTools;

// TODO: add priority levels to add control over overrides order (higher
// priority = included later in final css file) - see react-portal
typedef CssModule = {
	var path:String;
	var hash:String;
	var className:String;
	var styles:String;
	var clsInjection:Map<String, Type>;
}

class ReactCSSMacro {
	public static inline var BUILDER_KEY = 'REACT_CSS';
	public static inline var META_NAME = ':css';
	public static inline var BASE_DEFINE = 'react.css.base';
	public static inline var OUT_DEFINE = 'react.css.out';
	public static inline var SALT_DEFINE = 'react.css.salt';
	public static inline var SOURCEMAP_DEFINE = 'react.css.sourcemap';

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
		var meta = cls.meta.get().filter(m -> m.name == META_NAME)[0];
		if (meta.params.length == 0) return fields;

		hasChanged = true;
		var sourcemap = Context.defined(SOURCEMAP_DEFINE);
		var module = cls.module.split('.').pop();
		var path = cls.pack.concat([module, cls.name]).join('.');

		// TODO: detect collisions
		var key = path;
		if (Context.defined(SALT_DEFINE)) key = Context.definedValue(SALT_DEFINE) + key;
		var hash = Sha256.encode(path).substr(0, 6);
		var className = '${cls.name}-${hash}';

		for (f in fields) {
			if (f.name == "className") {
				// TODO: get rid of "Defined in this class?
				// TODO: only works with haxe development..
				Context.reportError('@:css needs to create a `className` field', meta.pos);
				Context.error('... But field is already declared here', f.pos);
			}
		}

		fields.push({
			name: "className",
			doc: "Generated CSS class name for this component",
			access: [AStatic, APublic],
			kind: FVar(macro :String, macro $v{className}),
			pos: meta.pos
		});

		// TODO: add support for Dynamic<Properties> (need a Properties => Stylesheet writer)
		var stylesExpr = meta.params[0];
		var styles = extractStyles(stylesExpr);

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
					case _: trace('TODO: error');
				}
			} catch (e) {
				trace('TODO: error');
				trace(e);
			}
			return r.matched(0);
		});

		initPersistentData();

		// Retype when this macro changes
		Context.registerModuleDependency(Context.getLocalModule(), thisModule);

		// TODO: store informations for source map if enabled
		cssModules.set(path, {
			path: path,
			hash: hash,
			className: className,
			styles: styles,
			clsInjection: clsInjection
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

			case _:
				Context.error('Cannot parse css source', expr.pos);
		};
	}

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

		if (base != null) buff.add(base + '\n');

		// TODO: source map if enabled
		if (cssModules == null) throw 'TODO';
		for (mod in cssModules) {
			var styles = mod.styles;

			for (ident => type in mod.clsInjection) {
				switch (type) {
					case TInst(_.get() => cls, _):
						var module = cls.module.split('.').pop();
						var path = cls.pack.concat([module, cls.name]).join('.');
						var def = cssModules.get(path);

						if (def == null) trace('TODO: error');
						else styles = styles.replace("$" + ident, '.' + def.className);

					case _:
						trace('TODO: error (should not be possible)');
				}
			}

			buff.add(styles + '\n');
		}

		// TODO: make it work [with parcel?]
		if (sourcemap) buff.add('/*# sourceMappingURL=${Context.definedValue(SOURCEMAP_DEFINE)} */\n');

		// trace(buff.toString());

		var dir = Path.directory(out);
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		File.saveContent(out, buff.toString());
	}
}
