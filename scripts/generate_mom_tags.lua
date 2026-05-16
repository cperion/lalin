-- Generate MOM tags from schema sources
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
require("moonlift.mom.build.tags_gen").write("lua/moonlift/mom/tags/mom_tags.lua")
