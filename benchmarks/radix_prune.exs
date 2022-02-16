alias Radix

# Why is recursive pruning as fast (or as slow)  as pruning once?

# Name                               ips        average  deviation         median         99th %
# prune_rdx8bit__recursive        5.32 K      187.88 μs    ±10.03%      177.69 μs      241.87 μs
# prune_rdx8bit__once             5.32 K      188.09 μs    ±10.76%      177.37 μs      251.10 μs
#
# Comparison: 
# prune_rdx8bit__recursive        5.32 K
# prune_rdx8bit__once             5.32 K - 1.00x slower +0.21 μs

# Name                               ips        average  deviation         median         99th %
# prune_rdx16bit_recursive         14.37       69.59 ms     ±2.97%       68.35 ms       76.58 ms
# prune_rdx16bit_once              14.27       70.06 ms     ±4.41%       68.48 ms       86.73 ms
#
# Comparison: 
# prune_rdx16bit_recursive         14.37
# prune_rdx16bit_once              14.27 - 1.01x slower +0.47 ms

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
