alias Radix

# % mix run benchmarks/radix_bit.exs
#
# Given a search key, the radix tree must be traversed while
# checking bit values at varying positions.  The speed at which
# a bit value can be determined depends on the search key representation:
# Key:           Extraction:
# bitstring      bitstring decomposition
# tuple of bits  elem(x) access
# integer        Bitwise funcs
# bitstring      erlang's binary.part
#
# Note:
# - tuples are limited in size to 2^24, so
# - integers can represent more bits
#
# Altx.make_key/1 creates the search key, then
# Altx.bit/3 gets the key, pos and max num of bits

# Name             ips        average  deviation         median         99th %
# k2_tuple     44.84 M       22.30 ns   ±583.23%          18 ns          89 ns
# k3_int       37.76 M       26.49 ns  ±3774.27%          21 ns         115 ns
# k1_bits       7.73 M      129.30 ns ±40581.14%          44 ns         163 ns
# k4_bin        3.81 M      262.63 ns ±21318.94%         139 ns         381 ns

# Comparison:
# k2_tuple     44.84 M
# k3_int       37.76 M - 1.19x slower +4.18 ns
# k1_bits       7.73 M - 5.80x slower +107.00 ns
# k4_bin        3.81 M - 11.78x slower +240.33 ns

defmodule Alt1 do
  # bitstring

  def make_key(key),
    do: key

  def bit(key, pos, max) do
    # key is a bitstring
    if pos < max do
      <<_::size(pos), bit::1, _::bitstring>> = key
      bit
    else
      0
    end
  end
end

defmodule Alt2 do
  # tuple
  def make_key(key) do
    k = for <<x::1 <- key>>, do: x
    List.to_tuple(k)
  end

  def bit(key, pos, max) do
    # key is tuple of bits
    if pos < max,
      do: elem(key, pos),
      else: 0
  end
end

defmodule Alt3 do
  # integer

  def make_key(key) do
    nbits = bit_size(key)
    <<num::size(nbits)>> = key
    num
  end

  def bit(key, pos, max) do
    # key is integer
    if pos < max do
      case :erlang.band(key, :erlang.bsl(1, max - pos - 1)) == 0 do
        false -> 1
        _ -> 0
      end
    else
      0
    end
  end
end

defmodule Alt4 do
  # erlang binary part

  def make_key(key),
    do: key

  def bit(key, pos, max) do
    if pos < max do
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
    else
      0
    end
  end
end

x = :rand.uniform(255)
y = :rand.uniform(255)
k_bits = <<x, y>>
k2_key = Alt2.make_key(k_bits)
k3_key = Alt3.make_key(k_bits)

IO.inspect(Alt1.bit(k_bits, 15, 16), label: :k1_bits)
IO.inspect(Alt2.bit(k2_key, 15, 16), label: :k2_tuple)
IO.inspect(Alt3.bit(k3_key, 15, 16), label: :k3_int)
IO.inspect(Alt4.bit(k_bits, 15, 16), label: :k4_binary)

Benchee.run(%{
  "k1_bits " => fn -> Alt1.bit(k_bits, 15, 16) end,
  "k2_tuple" => fn -> Alt2.bit(k2_key, 15, 16) end,
  "k3_int  " => fn -> Alt3.bit(k3_key, 15, 16) end,
  "k4_bin  " => fn -> Alt4.bit(k_bits, 15, 16) end
})

Benchee.run(%{
  "k2_tuple_key" => fn -> Alt2.make_key(k_bits) end,
  "k3_int_key  " => fn -> Alt3.make_key(k_bits) end
})
