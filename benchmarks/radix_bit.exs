alias Radix

# % mix run benchmarks/radix_bit.exs
#
# Given a search key, the radix tree must be traversed while
# checking bit values at varying positions.  The speed at which
# a bit value can be determined depends on the search key representation:
#
# Key:           Extraction:
# --------------------------------------
# bitstring      bitstring decomposition
# tuple of bits  elem(x) access
# integer        Bitwise funcs
# bitstring      erlang's binary.part
# --------------------------------------
#
# Note:
# - tuples are limited in size to 2^24, so
# - integers can represent more bits
#
# Altx.make_key/1 creates the search key, then
# Altx.bit/3 gets the key, pos and max num of bits

# IPv4 type bitstrings
# the_bits: <<192, 43, 192, 43>>
# k1_bits_: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0]
# k2_tuple: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0]
# k3_int__: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0]
# k4_int__: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0]

# Name               ips        average  deviation         median         99th %
# k3_int        402.56 K        2.48 μs   ±901.59%        2.20 μs        4.32 μs
# k4_int        401.28 K        2.49 μs   ±944.59%        2.22 μs        4.85 μs
# k1_bits       344.60 K        2.90 μs  ±1203.98%        2.50 μs        6.34 μs
# k2_tuple      317.60 K        3.15 μs   ±946.37%        2.82 μs        5.69 μs

# Comparison:
# k3_int        402.56 K
# k4_int        401.28 K - 1.00x slower +0.00792 μs
# k1_bits       344.60 K - 1.17x slower +0.42 μs
# k2_tuple      317.60 K - 1.27x slower +0.66 μs

# IPv6 type bitstrings
# Name               ips        average  deviation         median         99th %
# k1_bits       102.13 K        9.79 μs   ±190.78%        9.23 μs       22.07 μs
# k2_tuple       89.30 K       11.20 μs    ±72.84%       10.56 μs       21.18 μs
# k4_int         57.20 K       17.48 μs    ±41.97%       16.60 μs       37.77 μs
# k3_int         55.09 K       18.15 μs    ±90.91%       17.47 μs       34.47 μs

# Comparison:
# k1_bits       102.13 K
# k2_tuple       89.30 K - 1.14x slower +1.41 μs
# k4_int         57.20 K - 1.79x slower +7.69 μs
# k3_int         55.09 K - 1.85x slower +8.36 μs

# [[ Conclusion ]]
#
# Decomposing a bitstring is the fastest method.

defmodule Alt1 do
  # key is a bitstring

  def bit(key, pos, max) do
    if pos < max do
      <<_::size(pos), bit::1, _::bitstring>> = key
      bit
    else
      0
    end
  end

  def test(key) do
    # no need to convert key
    max = bit_size(key)
    for pos <- 0..max, do: bit(key, pos, max)
  end
end

defmodule Alt2 do
  # key is a tuple
  def make_key(key) do
    k = for <<x::1 <- key>>, do: x
    List.to_tuple(k)
  end

  # key is tuple of bits
  def bit(key, pos, max) do
    if pos < max,
      do: elem(key, pos),
      else: 0
  end

  def test(key) do
    max = bit_size(key)
    key = make_key(key)
    for pos <- 0..max, do: bit(key, pos, max)
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
    if :erlang.band(key, :erlang.bsl(1, max - pos - 1)) == 0,
      do: 0,
      else: 1
  end

  def test(key) do
    max = bit_size(key)
    key = make_key(key)
    for pos <- 0..max, do: bit(key, pos, max)
  end
end

defmodule Alt4 do
  # integer

  def make_key(key) do
    nbits = bit_size(key)
    <<num::size(nbits)>> = key
    num
  end

  def bit(key, pos, max) do
    :erlang.band(1, :erlang.bsr(key, max - pos - 1))
  end

  def test(key) do
    max = bit_size(key)
    key = make_key(key)
    for pos <- 0..max, do: bit(key, pos, max)
  end
end

x = :rand.uniform(255)
y = :rand.uniform(255)
key = <<x, y, x, y, x, y, x, y, x, y, x, y, x, y, x, y>>

IO.inspect(key, label: :the_bits)
IO.inspect(Alt1.test(key), label: :k1_bits_)
IO.inspect(Alt2.test(key), label: :k2_tuple)
IO.inspect(Alt3.test(key), label: :k3_int__)
IO.inspect(Alt4.test(key), label: :k4_int__)

Benchee.run(%{
  "k1_bits " => fn -> Alt1.test(key) end,
  "k2_tuple" => fn -> Alt2.test(key) end,
  "k3_int  " => fn -> Alt3.test(key) end,
  "k4_int " => fn -> Alt4.test(key) end
})
