Lady
====

Lady is a library to save and load savegames for games made in LÖVE. It is
based on the fast, robust, richly-featured table serialization library
[Ser](https://github.com/gvx/Ser).

Lady currently supports MiddleClass, SECS, hump.class and Slither. Pull
requests to add support for more class implementations are welcome.

30log is also supported, as long as you:

1. Don't call `tostring` on any loaded instance of a 30log class.
2. Don't have methods that make use of upvalues in any 30log class.

Like Ser itself, you can use, distribute and extend Lady under the terms of the
MIT license.

Using it
--------

(A more comprehensive reference can be found below.)

To use Lady, simply require it:

```lua
local lady = require 'lady'
```

Register all your classes at some point before saving or loading:

```lua
-- using MiddleClass:
local Player = lady.register_class(class('Player'))
-- using SECS:
local Player = lady.register_class(class:new(), 'Player')
-- using hump.class:
local Player = lady.register_class(class{}, 'Player')
-- using Slither:
class "Player" {
    __attributes__ = {lady.register_class}
}
-- if you prefer, you can register your classes in another place
-- for example, all in the same place:
lady.register_class(Player, 'Player')
lady.register_class(Enemy, 'Enemy')
lady.register_class(Goal, 'Goal')
```

When you want to save your game:

```lua
lady.save_all(user_input, player, enemy_list, goal_list)
```

And to load:

```lua
player, enemy_list, goal_list = lady.load_all(selected_name)
```

Reference
---------

###`lady.register_class(class[, classname])`

Registers `class`. It will be expected that the argument `classname` is
provided. If absent, `class.name` will be used instead. The name of the class
should be a string that contains a valid Lua identifier.

Names starting with an underscore are reserved and cannot be used for Lady.
Similarly, when using Slither, nested classnames (like `"foods.Cake"`) are not
supported. If you have classes with these kinds of names, provide a custom
classname to `lady.register_class`.

This function returns `class`, so it can be used as a decorator.

###`lady.save_all(filename, ...)`

Saves the values passed as additional arguments to the `filename` provided.
`love.filesystem` is used, so it can be found in the
[save directory](http://love2d.org/wiki/love.filesystem).

###`lady.load_all(filename)`

Returns the values saved in the `filename` provided. `love.filesystem` is used,
so it looks in the [save directory](http://love2d.org/wiki/love.filesystem).

The values are returned in the same order as they were passed to
`lady.save_all`.

No constructors will be called for any of the objects directly or indirectly
loaded.
