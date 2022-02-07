alias Radix

# % mix run benchmarks/radix_map_get.exs
# Radix is ~200-300 times slower than map for dense trees

# key: <<7, 171, 7, 171, 7, 171, 7, 171, 7, 171, 7, 171, 7, 171, 7, 171>>
# map: <<7, 171>>
# rdx: {<<7, 171, 7, 171, 7, 171, 7, 171, 7, 171, 7, 171, 7, 171, 7, 171>>, <<7, 171>>}

# Name                     ips        average  deviation         median         99th %
# map_get_sparse     1482.79 M        0.67 ns ±30021.03%           0 ns           0 ns
# map_get_dense       745.20 M        1.34 ns  ±7593.42%           0 ns           0 ns
# rdx_get_sparse       10.47 M       95.54 ns ±49091.15%           0 ns           0 ns
# rdx_get_dense         5.73 M      174.48 ns ±36906.11%           0 ns         551 ns

# Comparison: 
# map_get_sparse     1482.79 M
# map_get_dense       745.20 M - 1.99x slower +0.67 ns
# rdx_get_sparse       10.47 M - 141.67x slower +94.87 ns
# rdx_get_dense         5.73 M - 258.71x slower +173.80 ns

# IPv6 style bitstrings
keyvalues =
  for x <- 0..255, y <- 0..255, do: {<<x, y, x, y, x, y, x, y, x, y, x, y, x, y, x, y>>, <<x, y>>}

key =
  Enum.shuffle(keyvalues)
  |> List.first()
  |> elem(0)

rdx = Radix.new(keyvalues)
map = Enum.into(keyvalues, %{})

IO.inspect(key, label: :key)
IO.inspect(Map.get(map, key), label: :map)
IO.inspect(Radix.get(rdx, key), label: :rdx)

keyvalues2 = [{<<10, 10>>, 10}, {<<170, 170>>, 170}]
rdx_sparse = Radix.new(keyvalues2)
map_sparse = Enum.into(keyvalues2, %{})

Benchee.run(%{
  "map_get_dense" => fn -> Map.get(map, key) end,
  "rdx_get_dense" => fn -> Radix.get(rdx, key) end,
  "map_get_sparse" => fn -> Map.get(map_sparse, <<128, 128>>) end,
  "rdx_get_sparse" => fn -> Radix.get(rdx_sparse, <<128, 128>>) end
})
