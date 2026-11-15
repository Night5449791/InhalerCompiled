local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local delfile = delfile or function(file)
	writefile(file, '')
end

local function correct(path)
	return isfile(path) and select(1, readfile(path):find('--This watermark is used to delete the file if its cached, remove it to make the file persist after inhaler updates.', 1, true)) == 1
end

local function downloadFile(path, func)
	if not correct(path) then
		if isfile(path) then
			delfile(path)
		end

		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/Night5449791/InhalerCompiled/'..readfile('InhalerV4/profiles/commit.txt')..'/'..select(1, path:gsub('InhalerV4/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after inhaler updates.\n'..res
		end
		writefile(path, res)
	end
	return (func or readfile)(path)
end

local function wipeFolder(path)
	if not isfolder(path) then return end
	for _, file in listfiles(path) do
		if file:find('loader') then continue end
		if not correct(file) then
			delfile(file)
		end
	end
end

for _, folder in {'newvape', 'newvape/profiles', 'InhalerV4', 'InhalerV4/games', 'InhalerV4/assets', 'InhalerV4/libraries', 'InhalerV4/guis', 'InhalerV4/profiles'} do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

local function migrateFolder(old, new)
	if not isfolder(old) then return end
	if not isfolder(new) then
		makefolder(new)
	end

	for _, file in listfiles(old) do
		local name = file:match('[^/\\]+$')
		local target = new..'/'..name
		if name and not isfile(target) then
			writefile(target, readfile(file))
		end
	end
end

migrateFolder('newvape/games', 'InhalerV4/games')
migrateFolder('newvape/guis', 'InhalerV4/guis')
migrateFolder('newvape/libraries', 'InhalerV4/libraries')
migrateFolder('newvape/assets', 'InhalerV4/assets')
migrateFolder('newvape/profiles', 'InhalerV4/profiles')
if isfile('newvape/main.lua') and not isfile('InhalerV4/main.lua') then
	writefile('InhalerV4/main.lua', readfile('newvape/main.lua'))
end
for _, file in {'commit.txt', 'asset.txt'} do
	if isfile('newvape/profiles/'..file) and not isfile('InhalerV4/profiles/'..file) then
		writefile('InhalerV4/profiles/'..file, readfile('newvape/profiles/'..file))
	end
end
delfile('newvape/profiles/commit.txt')
delfile('newvape/profiles/asset.txt')

if not shared.VapeDeveloper then
	local _, subbed = pcall(function()
		return game:HttpGet('https://github.com/Night5449791/InhalerCompiled')
	end)

	local assetVer = '1'
	local commit = subbed:find('currentOid')
	commit = commit and subbed:sub(commit + 13, commit + 52) or nil
	commit = commit and #commit == 40 and commit or 'main'

	if commit == 'main' or (isfile('InhalerV4/profiles/commit.txt') and readfile('InhalerV4/profiles/commit.txt') or '') ~= commit then
		wipeFolder('InhalerV4')
		wipeFolder('InhalerV4/games')
		wipeFolder('InhalerV4/guis')
		wipeFolder('InhalerV4/libraries')
	end

	if (isfile('InhalerV4/profiles/asset.txt') and readfile('InhalerV4/profiles/asset.txt') or '') ~= assetVer then
		wipeFolder('InhalerV4/assets')
	end

	writefile('InhalerV4/profiles/asset.txt', assetVer)
	writefile('InhalerV4/profiles/commit.txt', commit)
end

return loadstring(downloadFile('InhalerV4/main.lua'), 'main')()