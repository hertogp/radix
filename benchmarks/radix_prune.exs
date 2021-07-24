alias Radix

# keyvalues = for x <- 0..255, y <- 0..255, z <- 0..15, do: {<<x, y, z::4>>, x}
keyvalues8 = for x <- 0..255, do: {<<x>>, x}
keyvalues16 = for x <- 0..255, y <- 0..255, do: {<<x, y>>, x}

rdx8bit = Radix.new(keyvalues8)
rdx16bit = Radix.new(keyvalues16)

fun = fn
  {_k0, _k1, v1, _k2, v2} -> v1 + v2
  {_k0, v0, _k1, v1, _k2, v2} -> v0 + v1 + v2
end

Benchee.run(%{
  "prune_rdx8bit__once" => fn -> Radix.prune(rdx8bit, fun) end,
  "prune_rdx8bit__recursive" => fn -> Radix.prune(rdx8bit, fun, recurse: true) end
})

Benchee.run(%{
  "prune_rdx16bit_once" => fn -> Radix.prune(rdx16bit, fun) end,
  "prune_rdx16bit_recursive" => fn -> Radix.prune(rdx16bit, fun, recurse: true) end
})
