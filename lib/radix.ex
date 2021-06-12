defmodule Radix do
  @moduledoc """
  A path-compressed Patricia trie, with one-way branching removed and
  bitstrings for keys.

  The radix tree (with r=2)  has 2 types of nodes:
  - *internal* `{bit, left, right}`, where `bit` >= 0
  - *leaf*     `[{key,value} ..]`

  where:
  - `bit` is the bit position to check in a key
  - `left` contains a subtree with keys whose `bit` is 0
  - `right` contains a subtree with keys whose `bit` is 1
  - `key` is a bitstring
  - `value` can be anything

  An `internal` node speficies a `bit` position to check in the search key to
  decide whether the traversal proceeds with its `left` or `right` subtree.

  A `leaf` stores key,value-pairs in a list sorted in descending order of
  key-length and all keys in a leaf have the other, shorter keys as their
  prefix.

  The keys stored below any given `internal` node or in a `leaf` node, all
  agree on the bits checked to arrive at that particular node.
  Path-compression means not all bits in a key are checked while traversing the
  tree, only those that differentiate between keys stored below the current
  `internal` node.  So a final match is needed to ensure a correct match.

  ## Examples

      iex> t = new()
      ...>     |> put(<<1, 1, 1>>, "1.1.1.0/24")
      ...>     |> put(<<1, 1, 1, 0::6>>, "1.1.1.0/30")
      iex>
      iex> lookup(t, <<1, 1, 1, 255>>)
      {<<1, 1, 1>>, "1.1.1.0/24"}
      #
      iex> lookup(t, <<1, 1, 1, 3>>)
      {<<1, 1, 1, 0::6>>, "1.1.1.0/30"}

  Regular binaries work too:

      iex> t = new([{"A.new", "new"}, {"A.newer", "newer"}, {"B.newest", "newest"}])
      iex> more(t, "A.") |> Enum.reverse()
      [{"A.new", "new"}, {"A.newer", "newer"}]
      #
      iex> lookup(t, "A.newest")
      {"A.new", "new"}
      #
      iex> more(t, "C.")
      []

  """

  @typedoc """
  A user supplied accumulator.
  """
  @type acc :: any()

  # maximum depth to travel the `t:tree/0` before inserting a new key.
  @typep bitpos :: non_neg_integer()

  @typedoc """
  Any value to be stored in the radix tree.
  """
  @type value :: any()

  @typedoc """
  A bitstring used as a key to index into the radix tree.
  """
  @type key :: bitstring()

  @typedoc """
  A radix leaf node.

  A leaf is either nil or a list of key,value-pairs sorted on key-length in
  descending order.

  """

  @type leaf :: [{key, value}] | nil

  @typedoc """
  A radix tree node.
  """
  @type tree :: {non_neg_integer, tree | leaf, tree | leaf}

  @empty {0, nil, nil}

  # Helpers

  # bit
  # - extract the value of a bit in a key
  # - bits beyond the key-length are considered `0`
  @spec bit(key, bitpos) :: 0 | 1
  defp bit(key, pos) when pos > bit_size(key) - 1,
    do: 0

  defp bit(key, pos) do
    <<_::size(pos), bit::1, _::bitstring>> = key
    bit
  end

  # follow key-path and return a leaf (which might be nil)
  # - inlining bit check doesn't really speed things up
  @spec leaf(tree | leaf, key, non_neg_integer) :: leaf
  defp leaf({bit, l, r}, key, max) when bit < max do
    <<_::size(bit), bit::1, _::bitstring>> = key

    case(bit) do
      0 -> leaf(l, key, max)
      1 -> leaf(r, key, max)
    end
  end

  defp leaf({_, l, _}, key, max),
    do: leaf(l, key, max)

  defp leaf(leaf, _key, _max),
    do: leaf

  # action to take given a new, candidate key and a leaf
  #  :take   if the leaf is nil and thus free
  #  :update if the candidate key is already present in the leaf
  #  :add    if the candidate shares the leaf's common prefix
  #  :split  if the candidate does not share the leaf's common prefix
  @spec action(leaf, key) :: :take | :update | :add | :split
  defp action(nil, _key),
    do: :take

  defp action([{k, _v} | _tail] = leaf, key) do
    pad1 = max(0, bit_size(key) - bit_size(k))
    pad2 = max(0, bit_size(k) - bit_size(key))

    case <<k::bitstring, 0::size(pad1)>> == <<key::bitstring, 0::size(pad2)>> do
      false -> :split
      true -> (keyget(leaf, key, bit_size(key)) && :update) || :add
    end
  end

  # say whether `k` is a prefix of `key`
  @spec prefix?(key, key) :: boolean
  defp prefix?(k, key) when bit_size(k) > bit_size(key),
    do: false

  defp prefix?(k, key) do
    len = bit_size(k)
    <<key::bitstring-size(len), _::bitstring>> = key
    k == key
  end

  # given a leaf and a key, return either {key, value} (exact match) or nil
  # - k,v-pairs in a leaf are sorted from longer -> shorter keys
  @spec keyget(leaf, key, non_neg_integer) :: {key, value} | nil
  defp keyget([{k, v} | _tail], key, _kmax) when k == key,
    do: {k, v}

  # stop checking once leaf keys are shorter than search key
  defp keyget([{k, _v} | _tail], _key, kmax) when bit_size(k) < kmax,
    do: nil

  defp keyget([{_k, _v} | tail], key, kmax),
    do: keyget(tail, key, kmax)

  defp keyget([], _key, _kmax), do: nil

  # get key's position (bitpos) in the tree
  # - if no leaf if found -> it's the last bit in the new key
  # - if a leaf is found
  #   -> if key is in leaf -> it's the leaf's position
  #   -> if key not in leaf -> it's the first bit that differs from leaf's 1st key
  @spec keypos(tree, key) :: bitpos
  defp keypos(tree, key) do
    max = bit_size(key)

    case keypos(tree, key, max, 0) do
      {_, nil} -> max(0, max - 1)
      {bitpos, leaf} -> (keyget(leaf, key, max) && bitpos) || keydiff(leaf, key)
    end
  end

  @spec keypos(tree, key, non_neg_integer, non_neg_integer) :: {non_neg_integer, leaf}
  defp keypos({bitpos, l, r}, key, max, _pos) when bitpos < max do
    <<_::size(bitpos), bit::1, _::bitstring>> = key

    case(bit) do
      0 -> keypos(l, key, max, bitpos)
      1 -> keypos(r, key, max, bitpos)
    end
  end

  # go left when beyond search key's length
  defp keypos({bitpos, l, _}, key, max, _pos),
    do: keypos(l, key, max, bitpos)

  defp keypos(leaf, _key, _max, bitpos),
    do: {bitpos, leaf}

  # given a leaf and a key, return either {key, value} (longest match) or nil
  @spec keylpm(leaf, key, non_neg_integer) :: {key, value} | nil
  defp keylpm([{k, _v} | tail], key, kmax) when bit_size(k) > kmax,
    do: keylpm(tail, key, kmax)

  defp keylpm([{k, v} | tail], key, kmax) do
    len = bit_size(k)
    <<key::bitstring-size(len), _::bitstring>> = key

    case k == key do
      true -> {k, v}
      false -> keylpm(tail, key, kmax)
    end
  end

  defp keylpm([], _key, _kmax), do: nil

  # differ
  # - find the first bit where two keys differ
  # - for two equal keys, the last bit's position is returned.
  # - returns the last bitpos if one key is a shorter prefix of the other
  #   in which case they both should belong to the same leaf.
  # - the bit position is used to determine where a k,v-pair is stored in the tree
  # - for a leaf, only need to check the first/longest key

  @spec keydiff(leaf, key) :: bitpos
  defp keydiff([{k, _v} | _tail], key),
    do: keydiff(k, key, 0)

  # stop recursion once longest key is exhausted
  @spec keydiff(key, key, bitpos) :: bitpos
  defp keydiff(k, key, pos) when pos < bit_size(k) or pos < bit_size(key) do
    case bit(key, pos) == bit(k, pos) do
      true -> keydiff(k, key, pos + 1)
      false -> pos
    end
  end

  # keep pos if outside both keys
  defp keydiff(_key1, _key2, pos),
    do: pos

  # API

  @doc """
  Return a new, empty radix tree.

  ## Example

      iex> new()
      {0, nil, nil}

  """
  @spec new :: tree
  def new,
    do: @empty

  @doc """
  Return a new radix tree, initialized using given list of {`key`, `value`}-pairs.

  ## Example

      iex> elements = [{<<1, 1>>, 16}, {<<1, 1, 1, 1>>, 32}, {<<1, 1, 0>>, 24}]
      iex> new(elements)
      {0,
        {23, [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}],
             [{<<1, 1, 1, 1>>, 32}]},
        nil
      }
  """
  @spec new([{key, value}]) :: tree
  def new([{key, _} | _tail] = elements) when is_bitstring(key),
    do: Enum.reduce(elements, @empty, fn {k, v}, t -> put(t, k, v) end)

  @doc """
  Get the key,value-pair whose key equals the given search `key`.

  If `key` is not present in the radix tree, `default` is returned.


  ## Example

      iex> elements = [{<<1, 1>>, 16}, {<<1, 1, 1>>, 24}, {<<1, 1, 1, 1>>, 32}]
      iex> ipt = new(elements)
      iex> get(ipt, <<1, 1, 1>>)
      {<<1, 1, 1>>, 24}
      iex> get(ipt, <<1, 1>>)
      {<<1, 1>>, 16}
      iex> get(ipt, <<1, 1, 0::1>>)
      nil
      iex> get(ipt, <<1, 1, 0::1>>, "oops")
      "oops"

  """
  @spec get(tree, key, any) :: {key, value} | any
  def get({0, _, _} = tree, key, default \\ nil) when is_bitstring(key) do
    kmax = bit_size(key)

    case leaf(tree, key, kmax) do
      nil -> default
      leaf -> keyget(leaf, key, kmax) || default
    end
  end

  @doc """
  Stores {`key`, `value`}-pairs in the radix `tree`.

  Any existing `key`'s will have their `value`'s replaced.

  ## Examples

      iex> elements = [{<<1, 1>>, "1.1.0.0/16"}, {<<1, 1, 1, 1>>, "1.1.1.1"}]
      iex> new() |> put(elements)
      {0,
        {23, [{<<1, 1>>, "1.1.0.0/16"}],
             [{<<1, 1, 1, 1>>, "1.1.1.1"}]},
        nil
      }

  """
  @spec put(tree, [{key, value}]) :: tree
  def put({0, _, _} = tree, [{k, _} | _tail] = elements) when is_bitstring(k),
    do: Enum.reduce(elements, tree, fn {k, v}, t -> put(t, k, v) end)

  @spec put(tree, key, value) :: tree
  @doc """
  Store a {`key`,`value`}-pair in the radix `tree`.

  Any existing `key` will have its `value` replaced.

  ## Examples

      iex> t = new()
      ...>  |> put(<<1, 1>>, "1.1.0.0/16")
      ...>  |> put(<<1, 1, 1, 1>>, "x.x.x.x")
      iex> t
      {0,
        {23, [{<<1, 1>>, "1.1.0.0/16"}],
             [{<<1, 1, 1, 1>>, "x.x.x.x"}]},
        nil
      }
      #
      iex> put(t, <<1, 1, 1, 1>>, "1.1.1.1")
      {0,
        {23, [{<<1, 1>>, "1.1.0.0/16"}],
             [{<<1, 1, 1, 1>>, "1.1.1.1"}]},
        nil
      }


  """
  def put({0, _, _} = tree, key, value) when is_bitstring(key) do
    put(tree, keypos(tree, key), key, value)
  end

  # put
  # - puts/updates a {key,value}-pair in the tree
  # - pos is maximum depth to travel down the tree before splitting

  # max depth exceeded, so split the tree here
  @spec put(tree | leaf, bitpos, key, value) :: tree | leaf
  defp put({bit, _left, _right} = node, pos, key, val) when pos < bit do
    case bit(key, pos) do
      0 -> {pos, [{key, val}], node}
      1 -> {pos, node, [{key, val}]}
    end
  end

  # put somewhere in the left/right subtree
  defp put({bit, l, r}, pos, key, val) do
    case bit(key, bit) do
      0 -> {bit, put(l, pos, key, val), r}
      1 -> {bit, l, put(r, pos, key, val)}
    end
  end

  # ran into a leaf
  defp put(leaf, pos, key, val) do
    case action(leaf, key) do
      :take ->
        [{key, val}]

      :split ->
        # split tree, new key decides if it goes left or right
        case bit(key, pos) do
          0 -> {pos, [{key, val}], leaf}
          1 -> {pos, leaf, [{key, val}]}
        end

      :add ->
        [{key, val} | leaf] |> List.keysort(0) |> Enum.reverse()

      :update ->
        List.keyreplace(leaf, key, 0, {key, val})
    end
  end

  @doc """
  Delete the entry from the `tree` for a specific `key` using an exact match.

  If `key` does not exist, the `tree` is returned unchanged.

  ## Example

      iex> elms = [{<<1,1>>, 16}, {<<1,1,0>>, 24}, {<<1,1,1,1>>, 32}]
      iex> t = new(elms)
      iex> t
      {0, {23, [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}],
               [{<<1, 1, 1, 1>>, 32}]
           },
        nil}
      #
      iex> delete(t, <<1, 1, 0>>)
      {0, {23, [{<<1, 1>>, 16}],
               [{<<1, 1, 1, 1>>, 32}]
           },
        nil}

  """
  @spec delete(tree, key) :: tree
  def delete({0, _, _} = tree, key) when is_bitstring(key),
    do: delp(tree, key)

  # delete a {k,v}-pair from the tree
  @spec delp(tree | leaf, key) :: tree | leaf
  defp delp({bit, l, r}, key) do
    case bit(key, bit) do
      0 -> delp({bit, delp(l, key), r})
      1 -> delp({bit, l, delp(r, key)})
    end
  end

  # key wasn't in the tree
  defp delp(nil, _key),
    do: nil

  # key leads to leaf
  defp delp(leaf, key) do
    case List.keydelete(leaf, key, 0) do
      [] -> nil
      leaf -> leaf
    end
  end

  # always keep the root, eliminate empty nodes and promote half-empty nodes
  defp delp({0, l, r}), do: {0, l, r}
  defp delp({_, nil, nil}), do: nil
  defp delp({_, l, nil}), do: l
  defp delp({_, nil, r}), do: r
  defp delp({bit, l, r}), do: {bit, l, r}

  @doc """
  Drops the given `keys` from the radix `tree` using an exact match.

  Any `key`'s that don't exist in the `tree`, are ignored.

  ## Example

      iex> elms = [{<<1, 1>>, 16}, {<<1, 1, 0>>, 24}, {<<1, 1, 1, 1>>, 32}]
      iex> t = new(elms)
      iex> t
      {0, {23, [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}],
               [{<<1, 1, 1, 1>>, 32}]
           },
        nil}
      #
      iex> drop(t, [<<1, 1>>, <<1, 1, 1, 1>>])
      {0, [{<<1, 1, 0>>, 24}], nil}

  """
  @spec drop(tree, [key]) :: tree
  def drop({0, _, _} = tree, keys) when is_list(keys),
    do: Enum.reduce(keys, tree, fn key, tree -> delete(tree, key) end)

  # get the longest prefix match for binary key
  # - follow tree path using key and get longest match from the leaf found
  # - more specific is to the right, less specific is to the left.
  # so:
  # - when left won't provide a match, the right will never match either
  # - however, if the right won't match, the left might still match

  @doc """
  Get the key,value-pair whose key is the longest prefix of `key`.

  ## Example

      iex> elms = [{<<1, 1>>, 16}, {<<1, 1, 0>>, 24}, {<<1, 1, 0, 0::1>>, 25}]
      iex> t = new(elms)
      iex> lookup(t, <<1, 1, 0, 127>>)
      {<<1, 1, 0, 0::1>>, 25}
      #
      iex> lookup(t, <<1, 1, 0, 128>>)
      {<<1, 1, 0>>, 24}
      #
      iex> lookup(t, <<1, 1, 1, 1>>)
      {<<1, 1>>, 16}
      #
      iex> lookup(t, <<2, 2, 2, 2>>)
      nil

  """
  @spec lookup(tree, key) :: {key, value} | nil
  def lookup({0, _, _} = tree, key) when is_bitstring(key),
    do: lookup(tree, key, bit_size(key))

  @spec lookup(tree | leaf, key, non_neg_integer) :: {key, value} | nil
  defp lookup({b, l, r} = _tree, key, kmax) when b < kmax do
    <<_::size(b), bit::1, _::bitstring>> = key

    case bit do
      0 -> lookup(l, key, kmax)
      1 -> lookup(r, key, kmax) || lookup(l, key, kmax)
    end
  end

  defp lookup({_, l, _}, key, kmax),
    do: lookup(l, key, kmax)

  defp lookup(nil, _key, _kmax),
    do: nil

  defp lookup(leaf, key, kmax),
    do: keylpm(leaf, key, kmax)

  @doc """
  Lookup given search `key` in `tree` and update the value of matched key with
  the given function.

  If `key` has a longest prefix match in `tree` then its value is passed to
  `fun` and its result is used as the updated value of the *matching* key. If
  `key` cannot be matched the {`default`, `key`}-pair is inserted in
  the `tree`.

  ## Examples

      iex> t = new()
      iex> t = update(t, <<1, 1, 1>>, 1, fn x -> x+1 end)
      iex> t
      {0, [{<<1, 1, 1>>, 1}], nil}
      iex> t = update(t, <<1, 1, 1>>, 1, fn x -> x+1 end)
      iex> t
      {0, [{<<1, 1, 1>>, 2}], nil}
      iex> t = update(t, <<1, 1, 1, 1>>, 1, fn x -> x+1 end)
      iex> t
      {0, [{<<1, 1, 1>>, 3}], nil}

  """
  @spec update(tree, key, value, (value -> value)) :: tree
  def update({0, _, _} = tree, key, default, fun)
      when is_bitstring(key) and is_function(fun, 1) do
    case lookup(tree, key) do
      nil -> put(tree, key, default)
      {k, value} -> put(tree, k, fun.(value))
    end
  end

  @doc """
  Returns all key-value-pair(s) whose key is a prefix for the given search `key`.

  Collects key,value-entries where the stored key is the same or less specific.

  ## Example

      iex> elements = [
      ...>  {<<1, 1>>, 16},
      ...>  {<<1, 1, 0>>, 24},
      ...>  {<<1, 1, 0, 0>>, 32},
      ...>  {<<1, 1, 1, 1>>, 32}
      ...> ]
      iex> t = new(elements)
      iex>
      iex> less(t, <<1, 1, 1, 1>>)
      [{<<1, 1, 1, 1>>, 32}, {<<1, 1>>, 16}]
      #
      iex> less(t, <<1, 1, 0>>)
      [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}]
      #
      iex> less(t, <<2, 2>>)
      []

  """
  @spec less(tree, key) :: [{key, value}]
  def less({0, _, _} = tree, key) when is_bitstring(key),
    do: lessp(tree, key)

  # all prefix matches: search key is prefix of stored key(s)
  @spec lessp(tree | leaf, key) :: [{key, value}] | []
  defp lessp({b, l, r} = _tree, key) do
    case bit(key, b) do
      0 -> lessp(l, key)
      1 -> lessp(r, key) ++ lessp(l, key)
    end
  end

  defp lessp(nil, _),
    do: []

  defp lessp(leaf, key),
    do: Enum.filter(leaf, fn {k, _} -> prefix?(k, key) end)

  @doc """
  Returns all key-value-pair(s) where the given search `key` is a prefix for a stored key.

  Collects key,value-entries where the stored key is the same or more specific.

  ## Example

      iex> elements = [
      ...>  {<<1, 1>>, 16},
      ...>  {<<1, 1, 0>>, 24},
      ...>  {<<1, 1, 0, 0>>, 32},
      ...>  {<<1, 1, 1, 1>>, 32}
      ...> ]
      iex> t = new(elements)
      iex>
      iex> more(t, <<1, 1, 0>>)
      [{<<1, 1, 0, 0>>, 32}, {<<1, 1, 0>>, 24}]
      #
      iex> more(t, <<1, 1, 1>>)
      [{<<1, 1, 1, 1>>, 32}]
      #
      iex> more(t, <<2>>)
      []

  """
  @spec more(tree, key) :: [{key, value}]
  def more({0, _, _} = tree, key) when is_bitstring(key),
    do: morep(tree, key)

  # reverse prefix match: stored key is prefix of search key
  @spec morep(tree | leaf, key) :: [{key, value}]
  defp morep({b, l, r} = _tree, key) when bit_size(key) < b do
    morep(r, key) ++ morep(l, key)
  end

  defp morep({b, l, r}, key) do
    # when bit b is zero, right subtree might hold longer keys that have key as a prefix
    # TODO: optimize; only call morep(r,key) when bitpos b > bit_size(key)
    case bit(key, b) do
      0 -> morep(l, key) ++ morep(r, key)
      1 -> morep(r, key)
    end
  end

  defp morep(nil, _),
    do: []

  defp morep(leaf, key),
    do: Enum.filter(leaf, fn {k, _} -> prefix?(key, k) end)

  @doc """
  Invokes `fun` for each key,value-pair in the radix tree with the accumulator.

  The initial value of the accumulator is `acc`. The function is invoked for
  each key,value-pair in the radix tree with the accumulator in a depth-first
  fashion. The result returned by the function is used as the accumulator for
  the next iteration.  The function returns the last accumulator.

  `fun`'s signature is (`t:key/0`, `t:value/0`, `t:acc/0`) -> `t:acc/0`.

  ## Example

      iex> t = new([
      ...>  {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
      ...>  {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
      ...>  {<<1, 1, 1>>, "1.1.1.0/24"},
      ...>  {<<3>>, "3.0.0.0/8"},
      ...>  ])
      iex>
      iex> # get values
      iex>
      iex> f = fn _key, value, acc -> [value | acc] end
      iex> reduce(t, [], f) |> Enum.reverse()
      ["1.1.1.0/25", "1.1.1.0/24", "1.1.1.128/25", "3.0.0.0/8"]

  """
  @spec reduce(tree, acc, (key, value, acc -> acc)) :: acc
  def reduce({0, _, _} = tree, acc, fun) when is_function(fun, 3),
    do: reducep(tree, acc, fun)

  @spec reducep(tree, acc, (key, value, acc -> acc)) :: acc
  defp reducep(tree, acc, fun)
  defp reducep(nil, acc, _fun), do: acc
  defp reducep([], acc, _fun), do: acc
  defp reducep({_, l, r}, acc, fun), do: reducep(r, reducep(l, acc, fun), fun)
  defp reducep([{k, v} | tail], acc, fun), do: reducep(tail, fun.(k, v, acc), fun)

  @doc """
  Return all key,value-pairs as a flat list.

  ## Example

      iex> tree = new([
      ...>  {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
      ...>  {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
      ...>  {<<3>>, "3.0.0.0/8"},
      ...>  {<<1, 1, 1>>, "1.1.1.0/24"}
      ...>  ])
      iex> to_list(tree)
      [
        {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
        {<<1, 1, 1>>, "1.1.1.0/24"},
        {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
        {<<3>>, "3.0.0.0/8"}
      ]


  """
  @spec to_list(tree) :: [{key, value}]
  def to_list({0, _, _} = tree) do
    tree
    |> reducep([], fn k, v, acc -> [{k, v} | acc] end)
    |> Enum.reverse()
  end

  @doc """
  Returns all keys from the radix `tree`.

  ## Example

      iex> t = new([
      ...>  {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
      ...>  {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
      ...>  {<<1, 1, 1>>, "1.1.1.0/24"},
      ...>  {<<3>>, "3.0.0.0/8"},
      ...>  ])
      iex>
      iex> keys(t)
      [<<1, 1, 1, 0::1>>, <<1, 1, 1>>, <<1, 1, 1, 1::1>>, <<3>>]
  """
  @spec keys(tree) :: [key]
  def keys({0, _, _} = tree) do
    tree
    |> reducep([], fn k, _v, acc -> [k | acc] end)
    |> Enum.reverse()
  end

  @doc """
  Returns all values from the radix `tree`.

  ## Example

      iex> t = new([
      ...>  {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
      ...>  {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
      ...>  {<<1, 1, 1>>, "1.1.1.0/24"},
      ...>  {<<3>>, "3.0.0.0/8"},
      ...>  ])
      iex>
      iex> # get values
      iex>
      iex> values(t)
      ["1.1.1.0/25", "1.1.1.0/24", "1.1.1.128/25", "3.0.0.0/8"]
  """
  @spec values(tree) :: [value]
  def values({0, _, _} = tree) do
    tree
    |> reducep([], fn _k, v, acc -> [v | acc] end)
    |> Enum.reverse()
  end

  @doc """
  Invokes `fun` on all (internal and leaf) nodes of the radix `tree` using either
  `:inorder`, `:preorder` or `:postorder` traversal.

  `fun` should have the signatures:
  -  (`t:acc/0`, `t:tree/0`) -> `t:acc/0`
  -  (`t:acc/0`, `t:leaf/0`) -> `t:acc/0`

  Note that `t:leaf/0` might be nil.

  ## Example

      iex> t = new([{<<1>>, 1}, {<<2>>, 2}, {<<3>>, 3}, {<<128>>, 128}])
      iex>
      iex> f = fn
      ...>   (acc, {_bit, _left, _right}) -> acc
      ...>   (acc, nil) -> acc
      ...>   (acc, leaf) -> acc ++ Enum.map(leaf, fn {_k, v} -> v end)
      ...> end
      iex>
      iex> traverse(t, [], f)
      [1, 2, 3, 128]

  """
  @spec traverse(tree, acc, (acc, tree | leaf -> acc), atom) :: acc
  def traverse({0, _, _} = tree, acc, fun, order \\ :inorder),
    do: traversep(acc, fun, tree, order)

  defp traversep(acc, fun, {bit, l, r}, order) do
    case order do
      :inorder ->
        acc
        |> traversep(fun, l, order)
        |> fun.({bit, l, r})
        |> traversep(fun, r, order)

      :preorder ->
        acc
        |> fun.({bit, l, r})
        |> traversep(fun, l, order)
        |> traversep(fun, r, order)

      :postorder ->
        acc
        |> traversep(fun, l, order)
        |> traversep(fun, r, order)
        |> fun.({bit, l, r})
    end
  end

  defp traversep(acc, fun, leaf, _order), do: fun.(acc, leaf)
end
