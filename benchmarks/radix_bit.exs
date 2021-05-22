alias Radix

# % mix run benchmarks/radix_bit.exs
#
# What is the fastest way to get the value of a single bit in a bitstring.
# Compare techniques based on:
# - bitstring & bitstring decomposition
# - tuple of 0's/1's & elem(x) access
# - integer & Bitwise funcs
# - erlang's binary.part

# Comparison:       ips
# k_bits        12.12 M
# k_int          5.92 M - 2.05x slower +86.44 ns
# k_bin          2.97 M - 4.08x slower +254.60 ns
# k_tuple        1.19 M - 10.17x slower +756.88 ns

defmodule Alt1 do
  # bitstring decode
  def bit(key, pos) when pos < bit_size(key) do
    <<_::size(pos), bit::1, _::bitstring>> = key
    bit
  end

  def bit(_key, _pos),
    do: 0
end

defmodule Alt2 do
  # tuple of 1's and 0's at the start, elem access to bits
  def bit(key, pos) do
    k = for <<x::1 <- key>>, do: x
    k = List.to_tuple(k)
    bit(k, pos, tuple_size(k))
  end

  def bit(key, pos, max) when pos < max do
    elem(key, pos)
  end

  def bit(_key, _pos, _max),
    do: 0
end

defmodule Alt3 do
  # integer with bitwise and

  def bit(key, pos) do
    nbits = bit_size(key)
    <<k_int::size(nbits)>> = key

    if pos < nbits do
      # bit(k_int, pos, nbits)
      case :erlang.band(k_int, :erlang.bsl(1, nbits - pos - 1)) != 0 do
        true -> 1
        _ -> 0
      end
    else
      0
    end
  end

  def bit(num, pos, max) when pos < max do
    case :erlang.band(num, :erlang.bsl(1, max - pos - 1)) != 0 do
      true -> 1
      _ -> 0
    end
  end

  def bit(_, _, _),
    do: 0
end

defmodule Alt4 do
  # erlang binary part
  def bit(key, pos) do
    <<byte>> = :binary.part(key, {div(pos, 8), 1})

    case rem(pos, 8) do
      0 -> :erlang.band(byte, 0x80)
      1 -> :erlang.band(byte, 0x40)
      2 -> :erlang.band(byte, 0x20)
      3 -> :erlang.band(byte, 0x10)
      4 -> :erlang.band(byte, 0x08)
      5 -> :erlang.band(byte, 0x04)
      6 -> :erlang.band(byte, 0x02)
      7 -> :erlang.band(byte, 0x01)
      _ -> raise "Oopsie"
    end
  end
end

x = :rand.uniform(255)
y = :rand.uniform(255)
k_bits = <<x, y>>

IO.inspect(Alt1.bit(k_bits, 15), label: :k_bits)
IO.inspect(Alt2.bit(k_bits, 15), label: :k_tuple)
IO.inspect(Alt3.bit(k_bits, 15), label: :k_int)
IO.inspect(Alt4.bit(k_bits, 15), label: :k_binary)

Benchee.run(%{
  "k_bits " => fn -> Alt1.bit(k_bits, 15) end,
  "k_tuple" => fn -> Alt2.bit(k_bits, 15) end,
  "k_int  " => fn -> Alt3.bit(k_bits, 15) end,
  "k_bin  " => fn -> Alt4.bit(k_bits, 15) end
})
