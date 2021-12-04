defmodule RadixError do
  defexception [:reason, :data]

  @moduledoc """
  RadixError provides information on error conditions that may occur.

  """

  @typedoc """
  An exception struct whose `reason` field contains a tuple with an error_id
  and the offending data.

  """
  @type t :: %__MODULE__{reason: atom(), data: any()}

  # inspect(data) might fill the screen if e.g. the tree is large, so limit the
  # amount of data provided by inspect.
  @limit 3

  def exception(reason, data),
    do: %__MODULE__{reason: reason, data: data}

  def message(%__MODULE__{reason: reason, data: data}),
    do: format(reason, data)

  defp hint(data, opts \\ []),
    do: "#{inspect(data, Keyword.put(opts, :limit, @limit))}"

  defp format(:badleaf, data),
    do: "expected a radix leaf node [{k,v},..], got #{hint(data)}"

  defp format(:badnode, data),
    do: "expected a valid radix node or leaf, got #{hint(data)}"

  defp format(:badkeyval, data),
    do: "expected a valid {key, value}-pair, got #{hint(data)}"

  # catch all in case some `reason`, `data` was missed here.
  defp format(reason, data),
    do: "TODO, describe error: #{reason} for #{hint(data)}"
end

defmodule Radix do
  @external_resource "README.md"

  @moduledoc File.read!("README.md")
             |> String.split("<!-- @MODULEDOC -->")
             |> Enum.fetch!(1)

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

  During tree traversals, bit positions in the key are checked in order
  to decide whether to go left (0) or right (1).  During these checks, bits
  beyond the current key's length always evaluate to 0.

  """
  @type key :: bitstring()

  @typedoc """
  A radix leaf node.

  A leaf is either nil or a list of key,value-pairs sorted on key-length in
  descending order.  All keys in a leaf have the other, shorter keys, as
  their prefix.

  """

  @type leaf :: [{key, value}] | nil

  @typedoc """
  An internal radix tree node.

  An internal node is a three element tuple: {`bit`, `left`, `right`}, where:
  - `bit` is the bit position to check in a key
  - `left` is a subtree with keys whose `bit` is 0
  - `right` is a subtree with keys whose `bit` is 1

  The keys stored below any given `internal` node, all agree on the bits
  checked to arrive at that particular node.

  Branches in the tree are only created when storing a new key,value-pair
  in the tree whose key does not agree with the leaf found during traversal.

  This path-compression means not all bits in a key are checked while
  traversing the tree, only those which differentiate the keys stored below the
  current `internal` node.  Hence, a final match is needed to ensure a correct
  match.

  """
  @type tree :: {non_neg_integer, tree | leaf, tree | leaf}

  @empty {0, nil, nil}

  # Helpers

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

  # consistent ArgumentError's
  @spec arg_err(atom, any) :: Exception.t()
  defp arg_err(:bad_keyvals, arg),
    do: ArgumentError.exception("expected a list of {key,value}-pairs, got #{inspect(arg)}")

  defp arg_err(:bad_tree, arg),
    do: ArgumentError.exception("expected a radix tree root node, got #{inspect(arg, limit: 3)}")

  defp arg_err(:bad_key, arg),
    do: ArgumentError.exception("expected a radix bitstring key, got: #{inspect(arg, limit: 3)}")

  defp arg_err(:bad_keys, arg),
    do:
      ArgumentError.exception(
        "expected a list of radix bitstring keys, got: #{inspect(arg, limit: 3)}"
      )

  defp arg_err(:bad_fun, {fun, arity}),
    do: ArgumentError.exception("expected a function with arity #{arity}, got #{inspect(fun)}")

  defp arg_err(:bad_callb, arg),
    do:
      ArgumentError.exception("unexpected callback return values, got #{inspect(arg, limit: 3)}")

  # bit
  # - extract the value of a bit in a key
  # - bits beyond the key-length are considered `0`
  @spec bit(key, bitpos) :: 0 | 1
  defp bit(<<>>, _pos), do: 0

  defp bit(key, pos) when pos > bit_size(key) - 1,
    do: 0

  defp bit(key, pos) do
    <<_::size(pos), bit::1, _::bitstring>> = key
    bit
  end

  # delete a {k,v}-pair from the tree
  @spec deletep(tree | leaf, key) :: tree | leaf
  defp deletep({bit, l, r}, key) do
    case bit(key, bit) do
      0 -> deletep({bit, deletep(l, key), r})
      1 -> deletep({bit, l, deletep(r, key)})
    end
  end

  # key wasn't in the tree
  defp deletep(nil, _key),
    do: nil

  # key leads to leaf
  defp deletep([{_, _} | _tail] = leaf, key) do
    case List.keydelete(leaf, key, 0) do
      [] -> nil
      leaf -> leaf
    end
  end

  # got a bad tree
  defp deletep(tree, _key),
    do: raise(error(:badnode, tree))

  # always keep the root, eliminate empty nodes and promote half-empty nodes
  defp deletep({0, l, r}), do: {0, l, r}
  defp deletep({_, nil, nil}), do: nil
  defp deletep({_, l, nil}), do: l
  defp deletep({_, nil, r}), do: r
  defp deletep({bit, l, r}), do: {bit, l, r}

  # a RadixError is raised for corrupt nodes or bad keys in a list
  @spec error(atom, any) :: RadixError.t()
  defp error(reason, data),
    do: RadixError.exception(reason, data)

  @spec flip(key) :: key
  defp flip(<<>>),
    do: <<>>

  defp flip(key) do
    pos = bit_size(key) - 1
    <<bits::bitstring-size(pos), bit::1>> = key

    case bit do
      0 -> <<bits::bitstring-size(pos), 1::1>>
      1 -> <<bits::bitstring-size(pos), 0::1>>
    end
  end

  # keydiff
  # - find the first bit where two keys differ
  # - but for two *equal* keys, the last bit's position is returned.
  # - if one key is a prefix for the other, returns the last bitpos of shorter key
  # - for a leaf, only need to check the first/longest key
  # - the bit position is used to determine if/when to branch the tree during put

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

  # given a leaf and a key, return either {key, value} (exact match) or nil
  # - k,v-pairs in a leaf are sorted from longer -> shorter keys
  @spec keyget(leaf, key, non_neg_integer) :: {key, value} | nil
  defp keyget([{k, v} | _tail], key, _kmax) when k == key,
    do: {k, v}

  # stop checking once leaf keys become shorter than search key
  defp keyget([{k, _v} | _tail], _key, kmax) when bit_size(k) < kmax,
    do: nil

  defp keyget([{_k, _v} | tail], key, kmax),
    do: keyget(tail, key, kmax)

  defp keyget([], _key, _kmax),
    do: nil

  defp keyget(nil, _key, _max),
    do: nil

  defp keyget(leaf, _key, _kmax),
    do: raise(error(:badleaf, leaf))

  # given a leaf and a key, return either {key, value} (longest match) or nil
  @spec keylpm(leaf, key, non_neg_integer) :: {key, value} | nil
  defp keylpm([{k, _v} | tail], key, kmax) when is_bitstring(k) and bit_size(k) > kmax,
    do: keylpm(tail, key, kmax)

  defp keylpm([{k, v} | tail], key, kmax) when is_bitstring(k) do
    len = bit_size(k)
    <<key::bitstring-size(len), _::bitstring>> = key

    case k == key do
      true -> {k, v}
      false -> keylpm(tail, key, kmax)
    end
  end

  defp keylpm([], _key, _kmax),
    do: nil

  defp keylpm(leaf, _key, _kmax),
    do: raise(error(:badleaf, leaf))

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

  # go left on masked off bits
  defp leaf({_, l, _}, key, max),
    do: leaf(l, key, max)

  # not a tuple, so it's a leaf
  defp leaf(leaf, _key, _max),
    do: leaf

  @spec lessp(tree | leaf, key) :: [{key, value}] | []
  defp lessp({b, l, r} = _tree, key) do
    case bit(key, b) do
      0 -> lessp(l, key)
      1 -> lessp(r, key) ++ lessp(l, key)
    end
  end

  defp lessp(nil, _),
    do: []

  defp lessp(leaf, key) do
    try do
      Enum.filter(leaf, fn {k, _} -> prefix?(k, key) end)
    rescue
      FunctionClauseError -> raise error(:badleaf, leaf)
    end
  end

  # get the longest prefix match for binary key
  # - follow tree path using key and get longest match from the leaf found
  # - more specific is to the right, less specific is to the left.
  # so:
  # - when left won't provide a match, the right will never match either
  # - however, if the right won't match, the left might still match

  @spec lookupp(tree | leaf, key, non_neg_integer) :: {key, value} | nil
  defp lookupp({b, l, r} = _tree, key, kmax) when b < kmax do
    <<_::size(b), bit::1, _::bitstring>> = key

    case bit do
      0 -> lookupp(l, key, kmax)
      1 -> lookupp(r, key, kmax) || lookupp(l, key, kmax)
    end
  end

  defp lookupp({_, l, _}, key, kmax),
    do: lookupp(l, key, kmax)

  defp lookupp(nil, _key, _kmax),
    do: nil

  defp lookupp(leaf, key, kmax),
    do: keylpm(leaf, key, kmax)

  defp match(opts) do
    case Keyword.get(opts, :match) do
      :longest -> &lookup/2
      :lpm -> &lookup/2
      _ -> &get/2
    end
  end

  # reverse prefix match: stored key is prefix of search key
  @spec morep(tree | leaf, key) :: [{key, value}]
  defp morep({b, l, r} = _tree, key) when bit_size(key) < b do
    morep(r, key) ++ morep(l, key)
  end

  defp morep({b, l, r}, key) do
    # when bit b is zero, right subtree might hold longer keys that have key as a prefix
    case bit(key, b) do
      0 -> morep(l, key) ++ morep(r, key)
      1 -> morep(r, key)
    end
  end

  defp morep(nil, _),
    do: []

  defp morep(leaf, key) do
    try do
      Enum.filter(leaf, fn {k, _} -> prefix?(key, k) end)
    rescue
      FunctionClauseError -> raise error(:badleaf, leaf)
    end
  end

  # store or append key,val under its parent key in given map
  @spec neighbors_collect(bitstring, any, map) :: map
  defp neighbors_collect(key, val, acc) do
    parent = trim(key)
    kids = Map.get(acc, parent, [])
    Map.put(acc, parent, [{key, val} | kids])
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

  # put
  # - puts/updates a {key,value}-pair in the tree
  # - pos is maximum depth to travel down the tree before splitting

  # max depth exceeded, so split the tree here
  @spec putp(tree | leaf, bitpos, key, value) :: tree | leaf
  defp putp({bit, _left, _right} = node, pos, key, val) when pos < bit do
    case bit(key, pos) do
      0 -> {pos, [{key, val}], node}
      1 -> {pos, node, [{key, val}]}
    end
  end

  # put somewhere in the left/right subtree
  defp putp({bit, l, r}, pos, key, val) do
    case bit(key, bit) do
      0 -> {bit, putp(l, pos, key, val), r}
      1 -> {bit, l, putp(r, pos, key, val)}
    end
  end

  # ran into a leaf
  defp putp(leaf, pos, key, val) do
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
        :lists.keyreplace(key, 1, leaf, {key, val})
    end
  end

  @spec reducep(tree, acc, (key, value, acc -> acc)) :: acc
  defp reducep(nil, acc, _fun), do: acc
  defp reducep([], acc, _fun), do: acc
  defp reducep({_, l, r}, acc, fun), do: reducep(r, reducep(l, acc, fun), fun)
  defp reducep([{k, v} | tail], acc, fun), do: reducep(tail, fun.(k, v, acc), fun)
  defp reducep(tree, _acc, _fun), do: raise(error(:badnode, tree))

  # remove the last bit of a key
  @spec trim(bitstring) :: bitstring
  defp trim(<<>>),
    do: <<>>

  defp trim(key) do
    len = bit_size(key) - 1
    <<bits::size(len), _::bitstring>> = key
    <<bits::size(len)>>
  end

  # internal node
  defp walkp(acc, fun, {bit, l, r}, order) do
    case order do
      :inorder ->
        acc
        |> walkp(fun, l, order)
        |> fun.({bit, l, r})
        |> walkp(fun, r, order)

      :preorder ->
        acc
        |> fun.({bit, l, r})
        |> walkp(fun, l, order)
        |> walkp(fun, r, order)

      :postorder ->
        acc
        |> walkp(fun, l, order)
        |> walkp(fun, r, order)
        |> fun.({bit, l, r})
    end
  end

  # leaf node
  defp walkp(acc, fun, [{k, _v} | _tail] = leaf, _order) when is_bitstring(k),
    do: fun.(acc, leaf)

  defp walkp(_acc, _fun, node, _order),
    do: raise(error(:badnode, node))

  # DOT helpers

  # annotate a tree with uniq numbers per node.  the result is no longer a
  # radix tree since all nodes are turned into {n, org_node}.  This makes
  # creating nodes and vertices much easier.
  defp annotate({0, _, _} = tree) do
    annotate(0, tree)
  end

  defp annotate(num, {b, l, r}) do
    l = annotate(num, l)
    r = annotate(elem(l, 0), r)
    {elem(r, 0) + 1, {b, l, r}}
  end

  defp annotate(num, nil),
    do: {num + 1, nil}

  defp annotate(num, leaf),
    do: {num + 1, leaf}

  # turn an annotated tree in a list of strings, describing the radix tree
  # as a digraph in the DOT-language (https://graphviz.org).
  defp dotify(annotated, opts) do
    label = Keyword.get(opts, :label, "radix")
    labelloc = Keyword.get(opts, :labelloc, "t")
    rankdir = Keyword.get(opts, :rankdir, "TB")
    ranksep = Keyword.get(opts, :ranksep, "0.5 equally")

    defs = dotify([], annotated, opts)

    [
      """
      digraph Radix {
        labelloc="#{labelloc}";
        label="#{label}";
        rankdir="#{rankdir}";
        ranksep="#{ranksep}";
      """
      | [defs, "}"]
    ]
  end

  defp dotify(acc, {n, {b, l, r}}, opts) do
    acc
    |> node(n, b, opts)
    |> vertex(n, l, "L")
    |> vertex(n, r, "R")
    |> dotify(l, opts)
    |> dotify(r, opts)
  end

  defp dotify(acc, {_n, nil}, _opts), do: acc
  defp dotify(acc, {n, leaf}, opts), do: node(acc, n, leaf, opts)

  defp kv_tostr({<<>>, _value}),
    do: "0/0"

  defp kv_tostr({key, _value}) when is_bitstring(key) do
    pad =
      case rem(bit_size(key), 8) do
        0 -> 0
        n -> 8 - n
      end

    bytes = for <<(x::8 <- <<key::bitstring, 0::size(pad)>>)>>, do: x
    "#{Enum.join(bytes, ".")}/#{bit_size(key)}"
  end

  defp kv_tostr(keyval),
    do: raise(error(:badkeyval, keyval))

  defp node(acc, id, bit, opts) when is_integer(bit) do
    bgcolor =
      case bit do
        0 -> Keyword.get(opts, :rootcolor, "orange")
        _ -> Keyword.get(opts, :nodecolor, "yellow")
      end

    [
      """
      N#{id} [label=<
        <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
          <TR><TD PORT="N#{id}" COLSPAN="2" BGCOLOR="#{bgcolor}">bit #{bit}</TD></TR>
          <TR><TD PORT=\"L\">0</TD><TD PORT=\"R\">1</TD></TR>
        </TABLE>
      >, shape="plaintext"];
      """
      | acc
    ]
  end

  defp node(acc, _id, nil, _opts), do: acc

  defp node(acc, id, leaf, opts) do
    bgcolor = Keyword.get(opts, :leafcolor, "green")
    kv_tostr = Keyword.get(opts, :kv_tostr, &kv_tostr/1)

    items =
      leaf
      |> Enum.map(kv_tostr)
      |> Enum.map(fn str -> "<TR><TD>#{str}</TD></TR>" end)

    [
      """
      N#{id} [label=<
        <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
          <TR><TD PORT="N#{id}" BGCOLOR="#{bgcolor}">leaf</TD></TR>
          #{Enum.join(items, "\n")}
        </TABLE>
        >, shape="plaintext"];
      """
      | acc
    ]
  end

  defp vertex(acc, _parent, {_, nil}, _port),
    do: acc

  defp vertex(acc, parent, {child, _}, port),
    do: ["N#{parent}:#{port} -> N#{child};\n" | acc]

  # API

  @doc ~S"""
  Returns a map where two neighboring key,value-pairs present in `tree`, are stored under their
  'parent' key.

  The parent key is 1 bit shorter than that of the two neighboring keys and stores:
  - `{key1, val1, key2, val2}`, or
  - `{key1, val1, key2, val2, val3}`

  If the parent key exists in the `tree` as well, its value is included as the
  fifth-element in the resulting tuple.

  ## Example

      iex> tree = new()
      ...> |> put(<<1, 1, 1, 0::6>>, "1.1.1.0/30")
      ...> |> put(<<1, 1, 1, 1::6>>, "1.1.1.4/30")
      ...> |> put(<<1, 1, 1, 2::6>>, "1.1.1.8/30")
      ...> |> put(<<1, 1, 1, 3::6>>, "1.1.1.12/30")
      ...> |> put(<<1, 1, 1, 1::5>>, "1.1.1.8/29")
      iex> adjacencies(tree)
      %{
        <<1, 1, 1, 0::5>> => {
          <<1, 1, 1, 0::6>>, "1.1.1.0/30",
          <<1, 1, 1, 1::6>>, "1.1.1.4/30"
        },
        <<1, 1, 1, 1::5>> => {
          <<1, 1, 1, 2::6>>, "1.1.1.8/30",
          <<1, 1, 1, 3::6>>, "1.1.1.12/30",
          "1.1.1.8/29"}
      }

  """
  @spec adjacencies(tree) :: map
  def adjacencies({0, _, _} = tree) do
    neighbors_keep = fn
      {parent, [{k2, v2}, {k1, v1}]}, acc ->
        case get(tree, parent) do
          {^parent, v3} -> Map.put(acc, parent, {k1, v1, k2, v2, v3})
          _ -> Map.put(acc, parent, {k1, v1, k2, v2})
        end

      _, acc ->
        acc
    end

    reduce(tree, %{}, &neighbors_collect/3)
    |> Enum.reduce(%{}, neighbors_keep)
  rescue
    err -> raise err
  end

  def adjacencies(tree),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Counts the number of entries by traversing given `tree`.

  ## Example

      iex> new([{<<>>, nil}, {<<1>>, 1}, {<<2>>, 2}])
      ...> |> count
      3
  """
  @spec count(tree) :: non_neg_integer
  def count({0, _, _} = tree) do
    reduce(tree, 0, fn _key, _value, acc -> acc + 1 end)
  rescue
    err -> raise err
  end

  def count(tree),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Deletes the entry from the `tree` for a specific `key` using an exact match.

  If `key` does not exist, the `tree` is returned unchanged.

  ## Example

      iex> elms = [{<<1,1>>, 16}, {<<1,1,0>>, 24}, {<<1,1,1,1>>, 32}]
      iex> t = new(elms)
      iex> t
      {0, {23, [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}],
               [{<<1, 1, 1, 1>>, 32}]
           },
        nil}
      iex> delete(t, <<1, 1, 0>>)
      {0, {23, [{<<1, 1>>, 16}],
               [{<<1, 1, 1, 1>>, 32}]
           },
        nil}

  """
  @spec delete(tree, key) :: tree
  def delete({0, _, _} = tree, key) when is_bitstring(key) do
    deletep(tree, key)
  rescue
    err -> raise err
  end

  def delete({0, _, _} = _tree, key),
    do: raise(arg_err(:bad_key, key))

  def delete(tree, _key),
    do: raise(arg_err(:bad_tree, tree))

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
      iex> drop(t, [<<1, 1>>, <<1, 1, 1, 1>>])
      {0, [{<<1, 1, 0>>, 24}], nil}

  """
  @spec drop(tree, [key]) :: tree
  def drop({0, _, _} = tree, keys) when is_list(keys) do
    Enum.reduce(keys, tree, fn key, tree when is_bitstring(key) -> delete(tree, key) end)
  rescue
    FunctionClauseError -> raise arg_err(:bad_keys, keys)
    err -> raise err
  end

  def drop({0, _, _} = _tree, keys),
    do: raise(arg_err(:bad_keys, keys))

  def drop(tree, _keys),
    do: raise(arg_err(:bad_tree, tree))

  @doc ~S"""
  Returns a list of lines describing the `tree` as a [graphviz](https://graphviz.org/) digraph.

  Options include:
  - `:label`, defaults to "radix")
  - `:labelloc`, defaults to "t"
  - `:rankdir`, defaults to "TB"
  - `:ranksep`, defaults to "0.5 equally"
  - `:rootcolor`, defaults to "orange"
  - `:nodecolor`, defaults to "yellow"
  - `:leafcolor`, defaults to "green"
  - `:kv_tostr`, defaults to an internal function that converts key to dotted decimal string (cidr style)

  If supplied via `:kv_tostr`, the function's signature must be ({`t:key/0`, `t:value/0`}) :: `t:String.t/0`
  and where the resulting string must be HTML-escaped.  See [html-entities](https://graphviz.org/doc/char.html).

  Works best for smaller trees.

  ## Example

      iex> t = new()
      ...> |> put(<<0, 0>>, "left")
      ...> |> put(<<1, 1, 1::1>>, "left")
      ...> |> put(<<128, 0>>, "right")
      iex> g = dot(t, label: "example")
      iex> File.write("assets/example.dot", g)
      :ok

   which, after converting with
   [dot](https://graphviz.org/doc/info/command.html), yields the following
   image:

   ![example](assets/example.dot.png)

  """
  @spec dot(tree, keyword()) :: list(String.t())
  def dot(tree, opts \\ [])

  def dot({0, _, _} = tree, opts) do
    tree
    |> annotate()
    |> dotify(opts)
    |> List.flatten()
  rescue
    err -> raise err
  end

  def dot(tree, _opts),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Returns true if `tree` is empty, false otherwise.

  ## Example

      iex> new() |> empty?()
      true

  """
  @spec empty?(tree) :: boolean
  def empty?({0, _, _} = tree),
    do: tree == @empty

  def empty?(tree),
    do: raise(error(:badtree, tree))

  @doc """
  Fetches the key,value-pair for a `key` in the given `tree`.

  Returns `{:ok, {key, value}}` or `:error` when `key` is not in the `tree`.  By
  default an exact match is used, specify `match: :lpm` to fetch based on a
  longest prefix match.

  ## Example

      iex> t = new([{<<>>, 0}, {<<1>>, 1}, {<<1, 1>>, 2}])
      iex> fetch(t, <<1, 1>>)
      {:ok, {<<1, 1>>, 2}}
      iex> fetch(t, <<2>>)
      :error
      iex> fetch(t, <<2>>, match: :lpm)
      {:ok, {<<>>, 0}}

  """
  @spec fetch(tree, key, keyword) :: {:ok, {key, value}} | :error
  def fetch(tree, key, opts \\ []) do
    case match(opts).(tree, key) do
      # case get(tree, key) do
      {k, v} -> {:ok, {k, v}}
      _ -> :error
    end
  rescue
    err -> raise err
  end

  @doc """
  Fetches the key,value-pair for a specific `key` in the given `tree`.

  Returns the `{key, value}`-pair itself, or raises a `KeyError` if `key` is
  not in the `tree`.  By default an exact match is used, specify `match: :lpm`
  to fetch based on a longest prefix match.

  ## Example

      iex> t = new([{<<1>>, 1}, {<<1, 1>>, 2}])
      iex> fetch!(t, <<1, 1>>)
      {<<1, 1>>, 2}
      iex> fetch!(t, <<2>>)
      ** (KeyError) key not found <<0b10>>
      iex> fetch!(t, <<1, 1, 1>>, match: :lpm)
      {<<1, 1>>, 2}

  """
  @spec fetch!(tree, key, keyword) :: {key, value}
  def fetch!(tree, key, opts \\ []) do
    case match(opts).(tree, key) do
      {k, v} -> {k, v}
      nil -> raise KeyError, "key not found #{inspect(key, base: :binary)}"
    end
  rescue
    err -> raise err
  end

  @doc """
  Returns the key,value-pair whose key equals the given search `key`, or
  `default`.

  If `key` is not a bitstring or not present in the radix tree, `default` is
  returned. If `default` is not provided, `nil` is used.


  ## Example

      iex> elements = [{<<1, 1>>, 16}, {<<1, 1, 1>>, 24}, {<<1, 1, 1, 1>>, 32}]
      iex> t = new(elements)
      iex> get(t, <<1, 1, 1>>)
      {<<1, 1, 1>>, 24}
      iex> get(t, <<1, 1>>)
      {<<1, 1>>, 16}
      iex> get(t, <<1, 1, 0::1>>)
      nil
      iex> get(t, <<1, 1, 0::1>>, :notfound)
      :notfound

  """
  @spec get(tree, key, any) :: {key, value} | any
  def get(tree, key, default \\ nil)

  def get({0, _, _} = tree, key, default) when is_bitstring(key) do
    kmax = bit_size(key)

    tree
    |> leaf(key, kmax)
    |> keyget(key, kmax) || default
  rescue
    err -> raise err
  end

  def get({0, _, _} = _tree, key, _default),
    do: raise(arg_err(:bad_key, key))

  def get(tree, _key, _default),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Updates a key,value-pair in `tree` by invoking `fun` with the result of an exact match.

  The callback `fun` is called with:
  - `{key, original_value}` if an exact match was found, or
  - `nil`, in case the key is not present in `tree`

  The callback function should return:
  - `{current_value, new_value}`, or
  - `:pop`.

  When `{current_value, new_value}` is returned, the `new_value` is stored
  under `key` and `{current_value, tree}` is returned.  When the callback
  passes back `:pop`, the `{key, original_value}`-pair is deleted from the
  `tree` and `{original_value, tree}` is returned.

  If the callback passes back `:pop` when its argument was `nil` then `{nil, tree}`
  is returned, where `tree` is unchanged.

  If something similar is required, but based on a longest prefix match, perhaps
  `Radix.update/3` or `Radix.update/4` is better suited.

  ## Examples

      # update stats, get org value and store new value
      iex> count = fn nil -> {0, 1}; {_key, val} -> {val, val+1} end
      iex> t = new([{<<1,1,1>>, 1}, {<<2, 2, 2>>, 2}])
      iex> {org, t} = get_and_update(t, <<1, 1, 1>>, count)
      iex> org
      1
      iex> get(t, <<1, 1, 1>>)
      {<<1, 1, 1>>, 2}
      iex> {org, t} = get_and_update(t, <<3, 3>>, count)
      iex> org
      0
      iex> get(t, <<3, 3>>)
      {<<3, 3>>, 1}

      # modify `count` callback so we get the new value back + updated tree
      iex> count = fn nil -> {1, 1}; {_key, val} -> {val+1, val+1} end
      iex> t = new([{<<1,1,1>>, 1}, {<<2, 2, 2>>, 2}])
      iex> {new, t} = get_and_update(t, <<1, 1, 1>>, count)
      iex> new
      2
      iex> get(t, <<1, 1, 1>>)
      {<<1, 1, 1>>, 2}
      iex> {new, t} = get_and_update(t, <<3, 3>>, count)
      iex> new
      1
      iex> get(t, <<3, 3>>)
      {<<3, 3>>, 1}

      # returning :pop deletes the key
      iex> once = fn nil -> {0, 1}; {_k, _v} -> :pop end
      iex> t = new([{<<1, 1>>, 1}])
      iex> {val, t} = get_and_update(t, <<2, 2>>, once)
      iex> val
      0
      iex> get(t, <<2, 2>>)
      {<<2, 2>>, 1}
      iex> {val, t} = get_and_update(t, <<1, 1>>, once)
      iex> val
      1
      iex> get(t, <<1, 1>>)
      nil

  """
  @spec get_and_update(tree, key, (nil | {key, value} -> {value, value} | :pop)) :: {value, tree}
  def get_and_update(tree, key, fun)

  def get_and_update({0, _, _} = tree, key, fun) when is_bitstring(key) and is_function(fun, 1) do
    org = get(tree, key)

    case fun.(org) do
      {cur, new} -> {cur, put(tree, key, new)}
      :pop -> if org != nil, do: {elem(org, 1), delete(tree, key)}, else: {org, tree}
      x -> raise(arg_err(:bad_callb, x))
    end
  rescue
    err -> raise err
  end

  def get_and_update({0, _, _} = _tree, key, fun) when is_bitstring(key),
    do: raise(arg_err(:bad_fun, {fun, 1}))

  def get_and_update({0, _, _} = _tree, key, fun) when is_function(fun, 1),
    do: raise(arg_err(:bad_key, key))

  def get_and_update(tree, _key, _fun),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Returns a list of all keys from the radix `tree`.

  ## Example

      iex> t = new([
      ...>  {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
      ...>  {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
      ...>  {<<1, 1, 1>>, "1.1.1.0/24"},
      ...>  {<<3>>, "3.0.0.0/8"},
      ...>  ])
      iex> keys(t)
      [<<1, 1, 1, 0::1>>, <<1, 1, 1>>, <<1, 1, 1, 1::1>>, <<3>>]

  """
  @spec keys(tree) :: [key]
  def keys({0, _, _} = tree) do
    tree
    |> reducep([], fn k, _v, acc -> [k | acc] end)
    |> Enum.reverse()
  rescue
    err -> raise err
  end

  def keys(tree),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Returns all key,value-pairs whose key is a prefix for the given search `key`.

  Collects key,value-pairs where the stored key is the same or less specific.
  Optionally exclude the search key from the results by providing option
  `:exclude` as true.

  ## Example

      # include search for less specifics
      iex> elements = [
      ...>  {<<1, 1>>, 16},
      ...>  {<<1, 1, 0>>, 24},
      ...>  {<<1, 1, 0, 0>>, 32},
      ...>  {<<1, 1, 1, 1>>, 32}
      ...> ]
      iex> t = new(elements)
      iex> less(t, <<1, 1, 1, 1>>)
      [{<<1, 1, 1, 1>>, 32}, {<<1, 1>>, 16}]
      iex> less(t, <<1, 1, 0>>)
      [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}]
      iex> less(t, <<2, 2>>)
      []
      #
      # exclusive search for less specifics
      #
      iex> less(t, <<1, 1, 0, 0>>, exclude: true)
      [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}]
      # 
      # search key itself does not have to exist in the tree
      iex> less(t, <<1, 1, 0, 25>>)
      [{<<1, 1, 0>>, 24}, {<<1, 1>>, 16}]


  """
  @spec less(tree, key, Keyword.t()) :: [{key, value}]
  def less(tree, key, opts \\ [])

  def less({0, _, _} = tree, key, opts) when is_bitstring(key) do
    result = lessp(tree, key)

    case Keyword.get(opts, :exclude, false) do
      true -> Enum.filter(result, fn {k, _v} -> k != key end)
      _ -> result
    end
  rescue
    err -> raise err
  end

  def less({0, _, _} = _tree, key, _opts),
    do: raise(arg_err(:bad_key, key))

  def less(tree, _key, _opts),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Returns the key,value-pair whose key is the longest prefix of `key`, or nil.

  Returns `{key, value}` or `nil` if there was no match.

  ## Example

      iex> elms = [{<<1, 1>>, 16}, {<<1, 1, 0>>, 24}, {<<1, 1, 0, 0::1>>, 25}]
      iex> t = new(elms)
      iex> lookup(t, <<1, 1, 0, 127>>)
      {<<1, 1, 0, 0::1>>, 25}
      iex> lookup(t, <<1, 1, 0, 128>>)
      {<<1, 1, 0>>, 24}
      iex> lookup(t, <<1, 1, 1, 1>>)
      {<<1, 1>>, 16}
      iex> lookup(t, <<2, 2, 2, 2>>)
      nil

  """
  @spec lookup(tree, key) :: {key, value} | nil
  def lookup({0, _, _} = tree, key) when is_bitstring(key) do
    lookupp(tree, key, bit_size(key))
  rescue
    err -> raise err
  end

  def lookup({0, _, _} = _tree, key),
    do: raise(arg_err(:bad_key, key))

  def lookup(tree, _key),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Merges two radix trees into one.

  Adds all key,value-pairs of `tree2` to `tree1`, overwriting any existing entries.

  ## Example

      iex> tree1 = new([{<<0>>, 0}, {<<1>>, 1}])
      iex> tree2 = new([{<<0>>, nil}, {<<2>>, 2}])
      iex> merge(tree1, tree2)
      ...> |> to_list()
      [{<<0>>, nil}, {<<1>>, 1}, {<<2>>, 2}]

  """
  @spec merge(tree, tree) :: tree
  def merge({0, _, _} = tree1, {0, _, _} = tree2) do
    reduce(tree2, tree1, fn k, v, t -> put(t, k, v) end)
  rescue
    err -> raise err
  end

  def merge({0, _, _} = _tree1, tree2),
    do: raise(arg_err(:bad_tree, tree2))

  def merge(tree1, _),
    do: raise(arg_err(:bad_tree, tree1))

  @doc """
  Merges two radix trees into one, resolving conflicts through `fun`.

  Adds all key,value-pairs of `tree2` to `tree1`, resolving conflicts through
  given `fun`.  Its arguments are the conflicting `t:key/0` and the `t:value/0`
  found in `tree1` and the `t:value/0` found in `tree2`.

  ## Example

      # keep values of tree1, like merge(tree2, tree1)
      iex> tree1 = new([{<<0>>, 0}, {<<1>>, 1}])
      iex> tree2 = new([{<<0>>, nil}, {<<2>>, 2}])
      iex> merge(tree1, tree2, fn _k, v1, _v2 -> v1 end)
      ...> |> to_list()
      [{<<0>>, 0}, {<<1>>, 1}, {<<2>>, 2}]

  """
  @spec merge(tree, tree, (key, value, value -> value)) :: tree
  def merge({0, _, _} = tree1, {0, _, _} = tree2, fun) when is_function(fun, 3) do
    f = fn k2, v2, t1 ->
      case get(t1, k2) do
        {_k1, v1} -> put(t1, k2, fun.(k2, v1, v2))
        nil -> put(t1, k2, v2)
      end
    end

    reduce(tree2, tree1, f)
  rescue
    err -> raise err
  end

  def merge({0, _, _} = _tree1, {0, _, _} = _tree2, fun),
    do: raise(arg_err(:bad_fun, {fun, 2}))

  def merge({0, _, _} = _tree1, tree2, _fun),
    do: raise(arg_err(:bad_tree, tree2))

  def merge(tree1, _tree2, _fun),
    do: raise(arg_err(:bad_tree, tree1))

  @doc """
  Returns all key,value-pairs where the given search `key` is a prefix for a stored key.

  Collects key,value-pairs where the stored key is the same or more specific.

  ## Example

      iex> elements = [
      ...>  {<<1, 1>>, 16},
      ...>  {<<1, 1, 0>>, 24},
      ...>  {<<1, 1, 0, 0>>, 32},
      ...>  {<<1, 1, 1, 1>>, 32}
      ...> ]
      iex> t = new(elements)
      iex> more(t, <<1, 1, 0>>)
      [{<<1, 1, 0, 0>>, 32}, {<<1, 1, 0>>, 24}]
      iex> more(t, <<1, 1, 1>>)
      [{<<1, 1, 1, 1>>, 32}]
      iex> more(t, <<2>>)
      []
      #
      # exclusive search for more specifics
      #
      iex> more(t, <<1, 1, 0>>, exclude: true)
      [{<<1, 1, 0, 0>>, 32}]
      #
      # search key itself does not have to exist
      #
      iex> more(t, <<1>>)
      [{<<1, 1, 1, 1>>, 32}, {<<1, 1, 0, 0>>, 32}, {<<1, 1, 0>>, 24}, {<<1, 1>>, 16}]



  """
  @spec more(tree, key, Keyword.t()) :: [{key, value}]
  def more(tree, key, opts \\ [])

  def more({0, _, _} = tree, key, opts) when is_bitstring(key) do
    result = morep(tree, key)

    case Keyword.get(opts, :exclude, false) do
      true -> Enum.filter(result, fn {k, _v} -> k != key end)
      _ -> result
    end
  rescue
    err -> raise err
  end

  def more({0, _, _} = _tree, key, _opts),
    do: raise(arg_err(:bad_key, key))

  def more(tree, _key, _opts),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Returns a new, empty radix tree.

  ## Example

      iex> new()
      {0, nil, nil}

  """
  @spec new :: tree
  def new(),
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
  def new(elements) when is_list(elements) do
    Enum.reduce(elements, @empty, fn {k, v}, t when is_bitstring(k) -> put(t, k, v) end)
  rescue
    FunctionClauseError -> raise arg_err(:bad_keyvals, elements)
  end

  def new(elements),
    do: raise(arg_err(:bad_keyvals, elements))

  @doc """
  Removes the value associated with `key` and returns the matched
  key,value-pair and the new tree.

  Options include:
  - `default: value`, returned if `key` could not be matched (defaults to nil)
  - `match: :lpm`, specifies a longest prefix match instead of an exact match

  If given search `key` was not matched, the tree is unchanged and the
  key,value-pair will be the search `key` and the default value.

  ## Examples

      # pop an existing element
      iex> new([{<<0>>, 0}, {<<1>>, 1}, {<<2>>, 2}])
      ...> |> pop(<<1>>)
      {
        {<<1>>, 1},
        {0, {6, [{<<0>>, 0}], [{<<2>>, 2}]}, nil}
      }

      # pop non-existing, using a default
      iex> new([{<<0>>, 0}, {<<1>>, 1}, {<<2>>, 2}])
      ...> |> pop(<<3>>, default: :notfound)
      {
        {<<3>>, :notfound},
        {0, {6, {7, [{<<0>>, 0}], [{<<1>>, 1}]}, [{<<2>>, 2}]}, nil}
      }

      # pop using longest prefix match
      iex> new([{<<1, 1, 1>>, "1.1.1.0/24"}, {<<1, 1, 1, 1::1>>, "1.1.1.128/25"}])
      ...> |> pop(<<1, 1, 1, 255>>, match: :lpm)
      {
        {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
        {0, [{<<1, 1, 1>>, "1.1.1.0/24"}], nil}
      }

  """
  @spec pop(tree, key, keyword) :: {value, tree}
  def pop(tree, key, opts \\ [])

  def pop({0, _, _} = tree, key, opts) when is_bitstring(key) do
    default = Keyword.get(opts, :default, nil)

    case match(opts).(tree, key) do
      nil -> {{key, default}, tree}
      {k, v} -> {{k, v}, delete(tree, k)}
    end
  rescue
    err -> raise err
  end

  def pop({0, _, _} = _tree, key, _opts),
    do: raise(arg_err(:bad_key, key))

  def pop(tree, _key, _opts),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Prunes given `tree` by invoking `fun` on adjacent keys.

  The callback `fun` is called with a 5- or 6-element tuple:
  - `{k0, k1, v1, k2, v2}`, for two adjacent keys `k1` and `k2` and absent parent `k0`
  - `{k0, v0, k1, v1, k2, v2}`, for two adjacent keys `k1` and `k2` with `v0` as parent `k0`'s value

  If `fun` returns `{:ok, value}` the children `k1` and `k2` are deleted from
  `tree` and `value` is stored under the parent key `k0`, overwriting any
  existing value.

  Optionally specify `recurse: true` to keep pruning as long as pruning changes
  the tree.  

  ## Examples

      iex> adder = fn {_k0, _k1, v1, _k2, v2} -> {:ok, v1 + v2}
      ...>            {_k0, v0, _k1, v1, _k2, v2} -> {:ok, v0 + v1 + v2}
      ...>         end
      iex> t = new()
      ...> |> put(<<1, 1, 1, 0::1>>, 1)
      ...> |> put(<<1, 1, 1, 1::1>>, 2)
      ...> |> put(<<1, 1, 0>>, 3)
      iex> # prune, once
      iex> prune(t, adder)
      {0, {23, [{<<1, 1, 0>>, 3}], [{<<1, 1, 1>>, 3}]}, nil}
      iex>  # prune, recursively
      iex> prune(t, adder, recurse: true)
      {0, [{<<1, 1, 0::size(7)>>, 6}], nil}

      iex> adder = fn {_k0, _k1, v1, _k2, v2} -> {:ok, v1 + v2}
      ...>            {_k0, v0, _k1, v1, _k2, v2} -> {:ok, v0 + v1 + v2}
      ...>         end
      iex> new(for x <- 0..255, do: {<<x>>, x})
      ...> |> prune(adder, recurse: true)
      {0, [{<<>>, 32640}], nil}
      iex> Enum.sum(0..255)
      32640

  """
  @spec prune(tree, (tuple -> nil | {:ok, value}), Keyword.t()) :: tree
  def prune(tree, fun, opts \\ [])

  def prune({0, _, _} = tree, fun, opts) when is_function(fun, 1) do
    reducer = pruner(fun)

    case Keyword.get(opts, :recurse, false) do
      false -> reduce(tree, tree, reducer)
      true -> prunep(tree, reducer)
    end
  end

  def prune({0, _, _} = _tree, fun, _opts),
    do: raise(arg_err(:bad_fun, {fun, 1}))

  def prune(tree, _fun, _opts),
    do: raise(arg_err(:bad_tree, tree))

  @spec prunep(tree, (key, value, acc -> acc)) :: tree
  defp prunep(tree, fun) do
    case reduce(tree, tree, fun) do
      ^tree -> tree
      changed -> prunep(changed, fun)
    end
  end

  @spec pruner((tuple -> nil | {:ok, any})) :: (key, value, tree -> tree)
  defp pruner(fun) do
    fn k2, v2, acc ->
      k0 = trim(k2)

      with 1 <- bit(k2, bit_size(k2) - 1),
           {k1, v1} <- get(acc, flip(k2)),
           parent <- get(acc, k0) do
        result =
          case parent do
            nil -> fun.({k0, k1, v1, k2, v2})
            {^k0, v0} -> fun.({k0, v0, k1, v1, k2, v2})
          end

        case result do
          {:ok, value} ->
            acc
            |> delete(k1)
            |> delete(k2)
            |> put(k0, value)

          _ ->
            acc
        end
      else
        _ -> acc
      end
    end
  end

  @doc """
  Stores the key,value-pairs from `elements` in the radix `tree`.

  Any existing `key`'s will have their `value`'s replaced.

  ## Example

      iex> elements = [{<<1, 1>>, "1.1.0.0/16"}, {<<1, 1, 1, 1>>, "1.1.1.1"}]
      iex> new()
      ...> |> put(elements)
      {0,
        {23, [{<<1, 1>>, "1.1.0.0/16"}],
             [{<<1, 1, 1, 1>>, "1.1.1.1"}]},
        nil
      }

  """
  @spec put(tree, [{key, value}]) :: tree
  def put({0, _, _} = tree, elements) when is_list(elements) do
    Enum.reduce(elements, tree, fn {k, v}, t when is_bitstring(k) -> put(t, k, v) end)
  rescue
    FunctionClauseError -> raise arg_err(:bad_keyvals, elements)
    err -> raise err
  end

  def put({0, _, _} = _tree, elements),
    do: raise(arg_err(:bad_keyvals, elements))

  def put(tree, _elements),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Stores the key,value-pair under `key` in the radix `tree`.

  Any existing `key` will have its `value` replaced.

  ## Example

      iex> t = new()
      ...>  |> put(<<1, 1>>, "1.1.0.0/16")
      ...>  |> put(<<1, 1, 1, 1>>, "x.x.x.x")
      iex> t
      {0,
        {23, [{<<1, 1>>, "1.1.0.0/16"}],
             [{<<1, 1, 1, 1>>, "x.x.x.x"}]},
        nil
      }
      iex> put(t, <<1, 1, 1, 1>>, "1.1.1.1")
      {0,
        {23, [{<<1, 1>>, "1.1.0.0/16"}],
             [{<<1, 1, 1, 1>>, "1.1.1.1"}]},
        nil
      }

  """
  @spec put(tree, key, value) :: tree
  def put({0, _, _} = tree, key, value) when is_bitstring(key) do
    putp(tree, keypos(tree, key), key, value)
  rescue
    err -> raise err
  end

  def put({0, _, _} = _tree, key, _value),
    do: raise(arg_err(:bad_key, key))

  def put(tree, _key, _value),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Invokes `fun` for each key,value-pair in the radix `tree` with the accumulator.

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
      iex> f = fn _key, value, acc -> [value | acc] end
      iex> reduce(t, [], f) |> Enum.reverse()
      ["1.1.1.0/25", "1.1.1.0/24", "1.1.1.128/25", "3.0.0.0/8"]

  """
  @spec reduce(tree, acc, (key, value, acc -> acc)) :: acc
  def reduce({0, _, _} = tree, acc, fun) when is_function(fun, 3) do
    reducep(tree, acc, fun)
  rescue
    err -> raise err
  end

  def reduce({0, _, _} = _tree, _acc, fun),
    do: raise(arg_err(:bad_fun, {fun, 3}))

  def reduce(tree, _acc, _fun),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Extracts the key,value-pairs associated with `keys` from `tree` into a new
  radix tree.

  Returns the new tree and the old tree with the key,value-pairs removed.
  By default an exact match is used, specify `match: :lpm` to match based
  on a longest prefix match.

  If none of the given `keys` match, the new tree will be empty and the old
  tree unchanged.

  ## Examples

      iex> tree = new([{<<0>>, 0}, {<<1>>, 1}, {<<2>>, 2}, {<<3>>, 3}])
      iex> {t1, t2} = split(tree, [<<0>>, <<2>>])
      iex> keys(t1)
      [<<0>>, <<2>>]
      iex> keys(t2)
      [<<1>>, <<3>>]

      iex> tree = new([{<<0>>, 0}, {<<1>>, 1}, {<<2>>, 2}, {<<3>>, 3}])
      iex> {t1, t2} = split(tree, [<<0, 0>>, <<2, 0>>], match: :lpm)
      iex> keys(t1)
      [<<0>>, <<2>>]
      iex> keys(t2)
      [<<1>>, <<3>>]

  """
  @spec split(tree, [key], keyword) :: {tree, tree}
  def split(tree, keys, opts \\ [])

  def split({0, _, _} = tree, keys, opts) when is_list(keys) do
    t = take(tree, keys, opts)
    {t, drop(tree, keys(t))}
  rescue
    err -> raise err
  end

  def split({0, _, _} = _tree, keys, _opts),
    do: raise(arg_err(:bad_keys, keys))

  def split(tree, _keys, _opts),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Returns a new tree with all the key,value-pairs whose key are in `keys`.

  If a key in `keys` does not exist in `tree`, it is ignored.

  By default keys are matched exactly, use the option `match: :lpm` to use
  longest prefix matching.

  ## Examples

      iex> new([{<<>>, nil}, {<<0>>, 0}, {<<1>>, 1}, {<<128>>, 128}, {<<255>>, 255}])
      ...> |> take([<<>>, <<1>>, <<255>>])
      ...> |> to_list()
      [{<<>>, nil}, {<<1>>, 1}, {<<255>>, 255}]

      # using longest prefix match
      iex> new([{<<>>, nil}, {<<0>>, 0}, {<<1>>, 1}, {<<128>>, 128}, {<<255>>, 255}])
      ...> |> take([<<2, 2, 2, 2>>, <<1, 1, 1, 1>>, <<255, 255, 0, 0>>], match: :lpm)
      ...> |> to_list()
      [{<<>>, nil}, {<<1>>, 1}, {<<255>>, 255}]

  """
  @spec take(tree, [key], keyword) :: tree
  def take(tree, keys, opts \\ [])

  def take({0, _, _} = tree, keys, opts) when is_list(keys) do
    fun = fn k, t when is_bitstring(k) ->
      case match(opts).(tree, k) do
        nil -> t
        {key, value} -> put(t, key, value)
      end
    end

    Enum.reduce(keys, @empty, fun)
  rescue
    FunctionClauseError -> raise arg_err(:bad_keys, keys)
    err -> raise err
  end

  def take({0, _, _} = _tree, keys, _opts),
    do: raise(arg_err(:bad_keys, keys))

  def take(tree, _keys, _opts),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Returns all key,value-pairs in `tree` as a flat list.

  ## Example

      iex> new([
      ...>  {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
      ...>  {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
      ...>  {<<3>>, "3.0.0.0/8"},
      ...>  {<<1, 1, 1>>, "1.1.1.0/24"}
      ...>  ])
      ...> |> to_list()
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
  rescue
    err -> raise err
  end

  def to_list(tree),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Updates a key,value-pair in `tree` by invoking `fun` after a longest prefix
  match lookup.

  After a longest prefix match lookup for given search `key`, the callback `fun`
  is called with:
  - `{matched_key, value}`, in case there was a match
  - `{original_key}`, in case there was no match

  If the callback `fun` returns
  - `{:ok, new_key, new_value}`, then _new_value_ will be stored under _new_key_ in the given `tree`
  - anything else will return the `tree` unchanged.

  Note that when `new_key` differs from `matched_key`, the latter is _not_
  deleted from the tree.  Because of the longest prefix match, the
  `matched_key` is provided to the callback `fun`.

  The main use case is for when dealing with full keys and doing statistics on
  some less specific level.  If an exact match is required,
  `Radix.get_and_update/3` might be a better fit.

  ## Examples

      iex> max24bits = fn key when bit_size(key) > 24 ->
      ...>                  <<bits::bitstring-size(24), _::bitstring>> = key; <<bits::bitstring>>
      ...>                key -> key
      ...>             end
      iex>
      iex> counter = fn {k, v} -> {:ok, k, v + 1}
      ...>              {k} -> {:ok, max24bits.(k), 1}
      ...>           end
      iex> new()
      ...> |> update(<<1, 1, 1, 1>>, counter)
      ...> |> update(<<1, 1, 1, 128>>, counter)
      ...> |> update(<<1, 1, 1, 255>>, counter)
      {0, [{<<1, 1, 1>>, 3}], nil}

      # only interested in known prefixes
      iex> counter = fn {k, v} -> {:ok, k, v + 1}
      ...>               _discard -> nil
      ...>           end
      iex> new()
      ...> |> put(<<1, 1, 1>>, 0)
      ...> |> update(<<1, 1, 1, 1>>, counter)
      ...> |> update(<<1, 1, 1, 2>>, counter)
      ...> |> update(<<2, 2, 2, 2>>, counter)
      {0, [{<<1, 1, 1>>, 2}], nil}

  """
  @spec update(tree, key, ({key} | {key, value} -> nil | {:ok, key, value})) :: tree
  def update({0, _, _} = tree, key, fun) when is_bitstring(key) and is_function(fun, 1) do
    result =
      case lookup(tree, key) do
        nil -> fun.({key})
        {k0, v0} -> fun.({k0, v0})
      end

    case result do
      {:ok, k, v} -> put(tree, k, v)
      _ -> tree
    end
  end

  def update({0, _, _} = _tree, key, fun) when is_bitstring(key),
    do: raise(arg_err(:bad_fun, {fun, 1}))

  def update({0, _, _} = _tree, key, fun) when is_function(fun, 1),
    do: raise(arg_err(:bad_key, key))

  def update(tree, _key, _fun),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Looks up the longest prefix match for given search `key` in `tree` and
  updates its value through `fun`.

  If `key` has a longest prefix match in `tree` then the associated value is
  passed to `fun` and its result is used as the updated value of the *matching*
  key. If `key` cannot be matched the {`key`, `default`}-pair is inserted in
  the `tree` without calling `fun`.

  ## Example

      iex> t = new()
      iex> t = update(t, <<1, 1, 1>>, 1, fn x -> x+1 end)
      iex> t
      {0, [{<<1, 1, 1>>, 1}], nil}
      iex> t = update(t, <<1, 1, 1, 0>>, 1, fn x -> x+1 end)
      iex> t
      {0, [{<<1, 1, 1>>, 2}], nil}
      iex> t = update(t, <<1, 1, 1, 255>>, 1, fn x -> x+1 end)
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
  rescue
    err -> raise err
  end

  def update(tree, key, _default, fun) when is_bitstring(key) and is_function(fun, 1),
    do: raise(arg_err(:bad_tree, tree))

  def update({0, _, _} = _tree, key, _val, fun) when is_bitstring(key),
    do: raise(arg_err(:bad_fun, {fun, 1}))

  def update(_tree, key, _default, _fun),
    do: raise(arg_err(:bad_key, key))

  @doc """
  Returns all values stored in the radix `tree`.

  ## Example

      iex> new([
      ...>  {<<1, 1, 1, 0::1>>, "1.1.1.0/25"},
      ...>  {<<1, 1, 1, 1::1>>, "1.1.1.128/25"},
      ...>  {<<1, 1, 1>>, "1.1.1.0/24"},
      ...>  {<<3>>, "3.0.0.0/8"},
      ...>  ])
      ...> |> values()
      ["1.1.1.0/25", "1.1.1.0/24", "1.1.1.128/25", "3.0.0.0/8"]

  """
  @spec values(tree) :: [value]
  def values({0, _, _} = tree) do
    tree
    |> reducep([], fn _k, v, acc -> [v | acc] end)
    |> Enum.reverse()
  rescue
    err -> raise err
  end

  def values(tree),
    do: raise(arg_err(:bad_tree, tree))

  @doc """
  Invokes `fun` on all (internal and leaf) nodes of the radix `tree` using either
  `:inorder`, `:preorder` or `:postorder` traversal.

  `fun` should have the signatures:
  -  (`t:acc/0`, `t:tree/0`) -> `t:acc/0`
  -  (`t:acc/0`, `t:leaf/0`) -> `t:acc/0`

  Note that `t:leaf/0` might be nil.

  ## Example

      iex> t = new([{<<1>>, 1}, {<<2>>, 2}, {<<3>>, 3}, {<<128>>, 128}])
      iex> f = fn
      ...>   (acc, {_bit, _left, _right}) -> acc
      ...>   (acc, nil) -> acc
      ...>   (acc, leaf) -> acc ++ Enum.map(leaf, fn {_k, v} -> v end)
      ...> end
      iex> walk(t, [], f)
      [1, 2, 3, 128]

  """
  @spec walk(tree, acc, (acc, tree | leaf -> acc), atom) :: acc
  def walk(tree, acc, fun, order \\ :inorder)

  def walk({0, _, _} = tree, acc, fun, order) when is_function(fun, 2) do
    walkp(acc, fun, tree, order)
  rescue
    err -> raise err
  end

  def walk({0, _, _} = _tree, _acc, fun, _order),
    do: raise(arg_err(:bad_fun, {fun, 2}))

  def walk(tree, _acc, _fun, _order),
    do: raise(arg_err(:bad_tree, tree))
end
