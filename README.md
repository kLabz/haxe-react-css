# React CSS

Compile-time "CSS in Haxe" library, allowing you to write your CSS in a per
component basis, only include the ones you actually use, and generate a good ol'
CSS file at compile time. No runtime CSS generation, no inline CSS.

Note that this lib is still in early alpha status, and doesn't catch corner
cases nicely; but is already usable.

## Installation

Only tested (for now) with latest Haxe version, and using [react-next][react-next]. This
should work with [haxe-react][haxe-react] too, or only with minor adjustments (PR welcome).

Version >= 0.9.0 of [css-types][css-types] is needed, unless you're using plain string CSS
in your components (see below).

This lib is still not released on haxelib, but you can install it with `haxelib
git`:

```sh
haxelib git react-css git@github.com:kLabz/haxe-react-css.git
# Or with https:
haxelib git react-css https://github.com/kLabz/haxe-react-css.git
```

## Basic setup

First, make sure you include this lib in your hxml with `-lib react-css`.
[css-types][css-types] being an optional dependency, add it too if you intend to
use object declaration syntax.

Configuration is made with defines:

```hxml
-D react.css.out=out/styles.css
-D react.css.base=base.css
```

* Use `react.css.out` define to set the ouput file for generated CSS
* `react.css.base` define is optional and points to a CSS file you want to
  include at the beginning of generated CSS file.

Other defines are available, see [Advanced usage](#advanced-usage).

For convenience, I can add those to your `import.hx` when working with [css-types][css-types]:

```haxe
import css.GlobalValue;
import css.GlobalValue.Var;
import react.ReactComponent;
import react.css.Stylesheet;
```

## Usage

There are several ways to declare your components' styles:
* External CSS file
* Inline CSS as `String` inside metadata
* Inline object declaration inside metadata, using [css-types][css-types]
* Object declaration as a static field, using [css-types][css-types]; this is
  the suggested way since it allows compile-time checks and completion

See below for details about each way. You can also find some examples in
[tests][tests].

Once your component's styles are defined, you can use `className` field anywhere
in your component (or from outside, it's `public static`):

```haxe
override function render():ReactFragment {
  return jsx(<div className={className}>My component</div>);
}
```

Whatever way you are using to define your components' styles, you can use this
in your CSS selectors to map to generated classnames:

* `_` is a shortcut to reference current component's generated classname

* `$SomeComponent` will resolve to `SomeComponent`'s classname (`SomeComponent`
  needs to be resolvable from current component, either by import or classic
  type resolution; fully qualified identifiers are not supported atm)

For example, this "plain CSS":
```css
_ {
  color: red;
}

_.selected + $SomeComponent {
  color: yellow;
}

_$SomeComponent$OtherComponent {
  color: blue;
}
```

Will generate:
```css
.MyComponent-abc123 {
  color: red;
}

.MyComponent-abc123.selected + .SomeComponent-def456 {
  color: yellow;
}

.MyComponent-abc123.SomeComponent-def456.OtherComponent-ghi789 {
  color: blue;
}
```

### External CSS file

Using an external CSS file for your component is possible with
`@:css(something.css)` meta on your component. Path resolution will be relative
to your component. You can omit quotes around path if it's simple enough (no
dashes, etc.).

```haxe
@:css(MyComponent.css)
class MyComponent extends ReactComponent {
  override function render():ReactFragment {
    return <div className={className}>My component</div>;
  }
}
```

### Plain CSS in metadata

You can also inline plain CSS inside the meta instead:

```haxe
@:css('
  _ {
    color: orange;
  }
')
class MyComponent extends ReactComponent {
  override function render():ReactFragment {
    return <div className={className}>My component</div>;
  }
}
```

### CSS object declaration in metadata

Using [css-types][css-types], you can use an object declaration inside the
metadata, similar to what can be done with [material-ui][material-ui]'s JSS.
Note that completion won't work there.

```haxe
@:css({
  '_': {
    color: 'red',
    position: Relative,
    fontSize: Inherit,
    padding: 42
  }
})
class MyComponent extends ReactComponent {
  override function render():ReactFragment {
    return <div className={className}>My component</div>;
  }
}
```

### CSS object declaration as static field

Last but definitely not least, you can declare a `styles` field with an object
declaration, using [css-types][css-types]:

```haxe
@:css
class MyComponent extends ReactComponent {
  static var styles:Stylesheet = {
    '_': {
      color: 'red',
      textAlign: Center,
      padding: 4,
      margin: [0, "0.3em"]
    },
    '_::before': {
      content: '"[before] "'
    },
    '$TestComponent + $OtherComponent': {
      position: Relative,
      '--blargh': 42,
      zIndex: Var('blargh')
    }
  };

  override function render():ReactFragment {
    return <div className={className}>My component</div>;
  }
}
```

Completion will work in there, for components identifiers and enum values. You
might want to use the `import.hx` example above for maximum convenience.

`styles` field will be removed during compilation, unless you explicitely tell
the build macro not to by adding a `@:keep` meta to it.

## Advanced usage

### Handle components order in generated CSS

CSS declaration order matters, and even if your CSS is defined on a
per-component basis, you can end up shadowing things you don't want to.

This should not happen a lot, but if you want to determine output order, add
`@:css.priority(X)` meta to your component(s), where `X` is any number. Higher
priority means that this component will be included later in output CSS.

### Use a salt to change all hashes

Hashes are calculated from your components path (and avoid clashes). If you want
a new set of hashes for some reason, you can define a salt with `react.css.salt`
define:

```hxml
-D react.css.salt=Aidohx7e
```

### Remap react-css meta/defines/field names

If meta/defines/field names used by this lib don't suit your needs for some
reason (clash with another lib, etc.), you can redefine them at compile time.

You can do that by redefining any of these in an init macro:

```haxe
package react.css;

// ...

class ReactCSSMacro {
  // ...

  public static var META_NAME = ':css';
  public static var PRIORITY_META_NAME = ':css.priority';

  public static var STYLES_FIELD = 'styles';
  public static var CLASSNAME_FIELD = 'className';

  public static var BASE_DEFINE = 'react.css.base';
  public static var OUT_DEFINE = 'react.css.out';
  public static var SALT_DEFINE = 'react.css.salt';
  public static var SOURCEMAP_DEFINE = 'react.css.sourcemap';

  // ...
}
```

https://github.com/kLabz/haxe-react-css/blob/9f3c3eea25989fb290dc190945c6ead3c7960a70/src/react/css/ReactCSSMacro.macro.hx#L32-L41

### Usage with classnames lib

Using [classnames][classnames] lib, you can do this:

```haxe
// I usually do this in import.hx
import classnames.ClassNames.fastNull as classNames;

// ...

override function render():ReactFragment {
  var classes = classNames({
    '$className': true,
    'selected': state.selected,
    'active': state.active,
  });

  return <div className={classes}>My component</div>;
}
```

Which will generate, with a state of `{selected: true, active: false}`:
```html
<div class="MyComponent-abc123 selected">My component</div>
```

## Limitations, roadmap

I intend to try to generate some sourcemaps for generated CSS, see [#1](https://github.com/kLabz/haxe-react-css/issues/1)

This lib is still in early alpha status, and doesn't catch corner cases nicely.
User errors will still often give bad error messages. If you get errors from
something that should work in your opinion, please let me know by opening an
issue.

[material-ui]: https://github.com/kLabz/haxe-material-ui
[react-next]: https://github.com/kLabz/haxe-react
[css-types]: https://github.com/kLabz/haxe-css-types
[haxe-react]: https://github.com/massiveinteractive/haxe-react
[classnames]: https://github.com/kLabz/haxe-classnames
[tests]: ./test/
