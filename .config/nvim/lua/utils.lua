_G.Repeatable = { last_cmd = nil }

function _G.repeatable(fn)
  return function()
    _G.Repeatable.last_cmd = fn
    fn()
  end
end
