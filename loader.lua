local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local delfile = delfile or function(file)
	writefile(file, '')
end

local watermarkStart = '--This watermark is used to delete the file if its cached, remove it to make the file persist after '
local watermark = watermarkStart..'inhaler updates.'

local function isWatermarked(path)
	local suc, res = pcall(function()
		return readfile(path)
	end)

	return suc and res ~= nil and res:sub(1, #watermarkStart) == watermarkStart
end

local function downloadFile(path, func)
	if not isfile(path) then
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/Night5449791/InhalerCompiled/'..readfile('newvape/profiles/commit.txt')..'/'..select(1, path:gsub('newvape/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('.lua') then
			res = watermark..'\n'..res
		end
		writefile(path, res)
	end
	return (func or readfile)(path)
end

local function wipeFolder(path, force)
	if not isfolder(path) then return end
	for _, file in listfiles(path) do
		if file:find('loader') then continue end
		if isfile(file) and (force or isWatermarked(file)) then
			delfile(file)
		end
	end
end

for _, folder in {'newvape', 'newvape/games', 'newvape/profiles', 'newvape/assets', 'newvape/libraries', 'newvape/guis'} do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

if not shared.VapeDeveloper then
	local _, subbed = pcall(function()
		return game:HttpGet('https://github.com/Night5449791/InhalerCompiled')
	end)

	local assetVer = '1'
	local cacheVer = '1'
	local commit = subbed:find('currentOid')
	commit = commit and subbed:sub(commit + 13, commit + 52) or nil
	commit = commit and #commit == 40 and commit or 'main'
	local storedCommit = isfile('newvape/profiles/commit.txt') and readfile('newvape/profiles/commit.txt') or ''
	local storedCache = isfile('newvape/profiles/cache.txt') and readfile('newvape/profiles/cache.txt') or ''

	if commit == 'main' or storedCommit ~= commit or storedCache ~= cacheVer then
		wipeFolder('newvape')
		wipeFolder('newvape/games')
		wipeFolder('newvape/guis')
		wipeFolder('newvape/libraries')
	end

	if (isfile('newvape/profiles/asset.txt') and readfile('newvape/profiles/asset.txt') or '') ~= assetVer then
		wipeFolder('newvape/assets', true)
	end

	writefile('newvape/profiles/asset.txt', assetVer)
	writefile('newvape/profiles/cache.txt', cacheVer)
	writefile('newvape/profiles/commit.txt', commit)
end

return loadstring(downloadFile('newvape/main.lua'), 'main')()