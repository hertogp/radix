alias Radix

keyvalues = for x <- 0..255, y <- 0..255, do: {<<x, y>>, <<x, y>>}

rdx = Radix.new(keyvalues)
map = Enum.into(keyvalues, %{})

Benchee.run(%{
  "map_get" => fn -> Map.get(map, <<128, 128>>) end,
  "rdx_get" => fn -> Radix.get(rdx, <<128, 128>>) end
})
