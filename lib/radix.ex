defmodule Radix do
  @moduledoc """
  A path-compressed Patricia trie, with one-way branching removed.

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
      iex> search(t, "A.") |> Enum.reverse()
      [{"A.new", "new"}, {"A.newer", "newer"}]
      #
      iex> lookup(t, "A.newest")
      {"A.new", "new"}
      #
      iex> search(t, "C.")
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
  """
  @type leaf :: [{key, value}] | nil

  @typedoc """
  A radix tree node.
  """
  @type tree :: {non_neg_integer, tree | leaf, tree | leaf}

  @empty {0, nil, nil}

  # Helpers

  # @compile {:inline, error: 2}
  # defp error(id, detail),
  #   do: RadixError.new(id, detail)

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
  @spec leaf(tree | leaf, key) :: leaf
  defp leaf({bit, l, r}, key) do
    case(bit(key, bit)) do
      0 -> leaf(l, key)
      1 -> leaf(r, key)
    end
  end

  defp leaf([{_k, _v} | _tail] = leaf, _key),
    do: leaf

  defp leaf(_, _key),
    do: nil

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
      true -> if List.keyfind(leaf, key, 0) == nil, do: :add, else: :update
    end
  end

  # say whether `k` is a prefix of `key`
  @spec is_prefix?(key, key) :: boolean
  defp is_prefix?(k, key) when bit_size(k) > bit_size(key),
    do: false

  defp is_prefix?(k, key) do
    len = bit_size(k)
    <<key::bitstring-size(len), _::bitstring>> = key
    k == key
  end

  # differ
  # - find the first bit where two keys differ
  # - for two equal keys, the last bit position is returned.
  # - returns the last bitpos if one key is a shorter prefix of the other
  #   in which case they both should belong to the same leaf.
  # the bit position is used to determine where a k,v-pair is stored in the tree

  # a leaf, only need to check the first/longest key
  @spec differ(leaf, key) :: bitpos
  defp differ([{k, _v} | _tail], key),
    do: diffkey(k, key, 0)

  # stop recursion once longest key is exhausted
  @spec diffkey(key, key, bitpos) :: bitpos
  defp diffkey(k, key, pos) when pos < bit_size(k) or pos < bit_size(key) do
    case bit(key, pos) == bit(k, pos) do
      true -> diffkey(k, key, pos + 1)
      false -> pos
    end
  end

  # keep pos if outside both keys
  defp diffkey(_key1, _key2, pos),
    do: pos

  # get key's position (bitpos) in the tree
  @spec position(tree, key) :: bitpos
  defp position(_tree, key) when bit_size(key) == 0,
    do: 0

  defp position(tree, key) do
    case leaf(tree, key) do
      nil -> bit_size(key) - 1
      leaf -> differ(leaf, key)
    end
  end

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
  Return a new radix tree, initialized using given list of `{key, value}`-pairs.

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
  Get the {k, v}-pair where `k` is equal to *key*.

  If *key* is not present in the radix tree, `default` is returned.


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
    # tree
    # |> leaf(key)
    # |> getp(key, default)
    case leaf(tree, key) do
      nil -> default
      leaf -> List.keyfind(leaf, key, 0, default)
    end
  end

  @doc """
  Store `{key, value}`-pairs in the radix tree, overwrites existing keys.

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
  Store a `value` under `key` in the radix tree.

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
  def put({0, _, _} = tree, key, value) when is_bitstring(key),
    do: put(tree, position(tree, key), key, value)

  # putp
  # - putps/updates a {key,value}-pair into the tree
  # - pos is maximum depth to travel down the tree before splitting

  # max depth exceeded, so split the tree here
  @spec put(tree | leaf, bitpos, key, value) :: tree | leaf
  defp put({bit, _left, _right} = node, pos, key, val) when pos < bit do
    case bit(key, pos) do
      0 -> {pos, [{key, val}], node}
      1 -> {pos, node, [{key, val}]}
    end
  end

  # putp somewhere in the left/right subtree
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

  Any `key`s that don't exist in the `tree`, are ignored.

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
  def drop({0, _, _} = tree, [k | _] = keys) when is_bitstring(k),
    do: Enum.reduce(keys, tree, fn key, tree -> delp(tree, key) end)

  # get the longest prefix match for binary key
  # - follow tree path using key and get longest match from the leaf found
  # - more specific is to the right, less specific is to the left.
  # so:
  # - when left won't provide a match, the right never will either
  # - however, if the right won't match, the left might still match

  @doc """
  Get the `{k,v}`-pair where `k` is the longest possible prefix of *key*.

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
    do: lpm(tree, key)

  @spec lpm(tree | leaf, key) :: {key, value} | nil
  defp lpm({b, l, r} = _tree, key) do
    case bit(key, b) do
      0 ->
        lpm(l, key)

      1 ->
        case lpm(r, key) do
          nil -> lpm(l, key)
          x -> x
        end
    end
  end

  defp lpm(nil, _key),
    do: nil

  defp lpm(leaf, key),
    do: Enum.find(leaf, fn {k, _} -> is_prefix?(k, key) end)

  @doc """
  Returns all key-value-pair(s) based on given search `key` and match `type`.

  - `:more` finds all key,value-pairs where search `key` is a prefix of key in tree
  - `:less` finds all key,value-pairs where key in tree is a prefix of the search `key`.

  The search type defaults to `:more` finding all key,value-pairs whose key matches the
  search `key`.  Includes search `key` in the results if present in the radix tree.

  ## Examples

      iex> elements = [
      ...>  {<<1, 1>>, 16},
      ...>  {<<1, 1, 0>>, 24},
      ...>  {<<1, 1, 0, 0>>, 32},
      ...>  {<<1, 1, 1, 1>>, 32}
      ...> ]
      iex> t = new(elements)
      iex> search(t, <<1, 1, 0>>)
      [{<<1, 1, 0, 0>>, 32}, {<<1, 1, 0>>, 24}]
      #
      iex> search(t, <<1, 1, 1>>)
      [{<<1, 1, 1, 1>>, 32}]
      #
      iex> search(t, <<2>>)
      []

      iex> t = new()
      ...>   |> put(<<1, 1>>, 16)
      ...>   |> put(<<1, 1, 0>>, 24)
      ...>   |> put(<<1, 1, 0, 0>>, 32)
      ...>   |> put(<<1, 1, 1, 1>>, 32)
      iex> search(t, <<1, 1, 1, 1>>, :less)
      [{<<1, 1, 1, 1>>, 32}, {<<1, 1>>, 16}]
      #
      iex> search(t, <<1, 1, 0>>, :less)
      [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}]
      #
      iex> search(t, <<2, 2>>, :less)
      []

  """
  @spec search(tree, key, atom) :: [{key, value}] | []
  def search(tree, key, type \\ :more)

  def search({0, _, _} = tree, key, :more) when is_bitstring(key),
    do: rpm(tree, key)

  def search({0, _, _} = tree, key, :less) when is_bitstring(key),
    do: apm(tree, key)

  # all prefix matches: search key is prefix of stored key(s)
  @spec apm(tree | leaf, key) :: [{key, value}]
  defp apm({b, l, r} = _tree, key) do
    case bit(key, b) do
      0 -> apm(l, key)
      1 -> apm(r, key) ++ apm(l, key)
    end
  end

  defp apm(nil, _),
    do: []

  defp apm(leaf, key),
    do: Enum.filter(leaf, fn {k, _} -> is_prefix?(k, key) end)

  # all reverse prefix matches: stored key is prefix of search key
  @spec rpm(tree | leaf, key) :: [{key, value}]
  defp rpm({b, l, r} = _tree, key) when bit_size(key) < b do
    rpm(r, key) ++ rpm(l, key)
  end

  defp rpm({b, l, r}, key) do
    # when bit b is zero, right subtree might hold longer keys that have key as a prefix
    # TODO: optimize; only call rpm(r,key) when bitpos b > bit_size(key)
    case bit(key, b) do
      0 -> rpm(l, key) ++ rpm(r, key)
      1 -> rpm(r, key)
    end
  end

  defp rpm(nil, _),
    do: []

  defp rpm(leaf, key),
    do: Enum.filter(leaf, fn {k, _} -> is_prefix?(key, k) end)

  @doc """
  Return all key,value-pairs as a flat list, using in-order traversal.

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
  def to_list(tree), do: to_list(tree, [])

  defp to_list(nil, acc), do: acc
  defp to_list({_bit, l, r}, acc), do: to_list(r, to_list(l, acc))
  defp to_list(leaf, acc), do: acc ++ leaf

  @doc """
  Invokes *fun* for each key,value-pair in the radix tree with the accumulator.

  The initial value of the accumulator is `acc`. The function is invoked for
  each key,value-pair in the radix tree with the accumulator in a depth-first
  fashion. The result returned by the function is used as the accumulator for
  the next iteration.  The function returns the last accumulator.

  *fun*'s signature is (`t:key/0`, `t:value/0`, `t:acc/0`) -> `t:acc/0`.

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
      iex> reduce(t, f, []) |> Enum.reverse()
      ["1.1.1.0/25", "1.1.1.0/24", "1.1.1.128/25", "3.0.0.0/8"]

  """
  @spec reduce(tree, (key, value, acc -> acc), acc) :: acc
  def reduce({0, _, _} = tree, fun, acc) when is_function(fun, 3),
    do: reducep(tree, fun, acc)

  @spec reducep(tree, (key, value, acc -> acc), acc) :: acc
  def reducep(tree, fun, acc)
  def reducep(nil, _f, acc), do: acc
  def reducep([], _f, acc), do: acc
  def reducep({_, l, r}, fun, acc), do: reducep(r, fun, reducep(l, fun, acc))
  def reducep([{k, v} | tail], fun, acc), do: reducep(tail, fun, fun.(k, v, acc))

  @doc """
  Invokes *fun* on all (internal and leaf) nodes of the radix tree using either
  `:inorder`, `:preorder` or `:postorder` traversal.

  *fun* should have the signatures:
  -  (`t:acc/0`, `t:tree/0`) -> `t:acc/0`
  -  (`t:acc/0`, `t:leaf/0`) -> `t:acc/0`

  Note that *leaf* might be nil.

  ## Example

      iex> t = new([
      ...>  {<<1, 1>>, "1.1"},
      ...>  {<<1, 1, 0>>, "1.1.0"},
      ...>  {<<1, 1, 0, 0>>, "1.1.0.0"},
      ...>  {<<1, 1, 1, 1>>, "1.1.1.1"}
      ...>  ])
      iex>
      iex> f = fn
      ...>   (acc, {_bit, _left, _right}) -> acc
      ...>   (acc, nil) -> acc
      ...>   (acc, leaf) -> Enum.map(leaf, fn {_k, v} -> v end) ++ acc
      ...> end
      iex>
      iex> traverse(t, f, [])
      ["1.1.1.1", "1.1.0.0", "1.1.0", "1.1"]

  """
  @spec traverse(tree, (acc, tree | leaf -> acc), acc, atom) :: acc
  def traverse(tree, fun, acc, order \\ :inorder),
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
