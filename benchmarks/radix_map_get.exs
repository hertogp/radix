alias Radix

keyvalues = for x <- 0..255, y <- 0..255, do: {<<x, y>>, <<x, y>>}

rdx = Radix.new(keyvalues)
map = Enum.into(keyvalues, %{})

keyvalues2 = [{<<10, 10>>, 10}, {<<170, 170>>, 170}]
rdx_sparse = Radix.new(keyvalues2)
map_sparse = Enum.into(keyvalues2, %{})

Benchee.run(%{
  "map_get_dense" => fn -> Map.get(map, <<128, 128>>) end,
  "rdx_get_dense" => fn -> Radix.get(rdx, <<128, 128>>) end,
  "map_get_sparse" => fn -> Map.get(map_sparse, <<128, 128>>) end,
  "rdx_get_sparse" => fn -> Radix.get(rdx_sparse, <<128, 128>>) end
})
