alias Radix

# [[ rdx8 ]]

# Name                               ips        average  deviation         median         99th %
# prune_rdx8bit__once             1.57 K        0.64 ms     ±9.76%        0.62 ms        0.94 ms
# prune_rdx8bit__recursive        0.83 K        1.20 ms     ±8.17%        1.17 ms        1.63 ms
#
# Comparison:
# prune_rdx8bit__once             1.57 K
# prune_rdx8bit__recursive        0.83 K - 1.88x slower +0.56 ms

# [[ rdx16 ]]
# Name                               ips        average  deviation         median         99th %
# prune_rdx16bit_once               3.36      297.62 ms     ±3.18%      297.12 ms      315.77 ms
# prune_rdx16bit_recursive          1.78      561.30 ms     ±2.56%      561.57 ms      588.24 ms
#
# Comparison:
# prune_rdx16bit_once               3.36
# prune_rdx16bit_recursive          1.78 - 1.89x slower +263.68 ms

keyvalues8 = for x <- 0..255, do: {<<x>>, x}
keyvalues16 = for x <- 0..255, y <- 0..255, do: {<<x, y>>, x}

rdx8bit = Radix.new(keyvalues8)
rdx16bit = Radix.new(keyvalues16)

fun = fn
  {_k0, _k1, v1, _k2, v2} -> {:ok, v1 + v2}
  {_k0, v0, _k1, v1, _k2, v2} -> {:ok, v0 + v1 + v2}
end

rdx8bit
|> Radix.count()
|> IO.inspect(label: :rdx8bit_org)

rdx8bit
|> Radix.prune(fun)
|> Radix.count()
|> IO.inspect(label: :rdx8bit_once)

rdx8bit
|> Radix.prune(fun, recurse: true)
|> Radix.count()
|> IO.inspect(label: :rdx8bit_recurse)

rdx16bit
|> Radix.count()
|> IO.inspect(label: :rdx16bit_org)

rdx16bit
|> Radix.prune(fun)
|> Radix.count()
|> IO.inspect(label: :rdx16bit_once)

rdx16bit
|> Radix.prune(fun, recurse: true)
|> Radix.count()
|> IO.inspect(label: :rdx16bit_recurse)

Benchee.run(%{
  "prune_rdx8bit__once" => fn -> Radix.prune(rdx8bit, fun) end,
  "prune_rdx8bit__recursive" => fn -> Radix.prune(rdx8bit, fun, recurse: true) end
})

Benchee.run(%{
  "prune_rdx16bit_once" => fn -> Radix.prune(rdx16bit, fun) end,
  "prune_rdx16bit_recursive" => fn -> Radix.prune(rdx16bit, fun, recurse: true) end
})
