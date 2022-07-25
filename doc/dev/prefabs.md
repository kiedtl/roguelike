% Prefabs are done with a simple markup language.
%
% Comments are done with a single percent mark.
%
% Legend:
%    #   wall
%    .   floor
%    •   lamp
%    *   connection
%    ˜   shallow water terrain
%    ~   water
%    ≈   lava
%    &   window
%    +   door
%    ±   locked door
%    ≡   bars
%    =   ring
%    ?   anything
%    α   depends on level
%    β   depends on level
%    γ   depends on level
%    L   any non-rare loot item
%    R   any rare loot item
%    C   a goblin-prisoner corpse
%
% Metadata:
%    :g_global_restriction <number>
%        Set a restriction on how many times a prefab can be used across the
%        entire dungeon.
%        Global.
%
%    :g_nopadding
%        Don't require enough space for an empty floor padding.
%        Global.
%
%    :subroom_area <x>,<y> <height> <width> [prefab_id]
%        Try to place a subroom in the following rectangle. May take an optional
%        prefab id.
%        Reset on /.
%
%    :material <name>
%        Use <name> as the material for floor and wall tiles.
%        Reset on /.
%
%    :center_align
%        Disallow placing a subroom if it wouldn't be aligned in the center of
%        the parent room.
%

% Example:

?##*##?
##...##
#.....#
*.....*
#.....#
##...##
?##*##?
