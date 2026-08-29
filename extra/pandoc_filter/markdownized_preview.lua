image_count = 0

function Image(el)
  image_count = image_count + 1

  local alt = pandoc.utils.stringify(el.caption)

  if alt == "" then
    local ext = el.src:match("%.([^.]+)$") or "img"
    alt = image_count .. "." .. ext
  end

  return pandoc.Str("[🖼️ " .. alt .. "] ")
end