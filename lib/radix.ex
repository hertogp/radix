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
  #

  # consistent ArgumentError's
  defp bad_tree(arg),
    do: ArgumentError.exception("expected a radix tree root node, got #{inspect(arg, limit: 3)}")

  defp bad_key(arg),
    do:
      ArgumentError.exception("expected a radix key (bitstring), got: #{inspect(arg, limit: 3)}")

  defp bad_keys(arg),
    do:
      ArgumentError.exception(
        "expected a list of radix keys (bitstring), got: #{inspect(arg, limit: 3)}"
      )

  defp bad_list(arg),
    do: ArgumentError.exception("expected a list of {key,value}-pairs, got #{inspect(arg)}")

  defp bad_fun(arg, arity),
    do: ArgumentError.exception("expected a function with arity #{arity}, got #{inspect(arg)}")

  # a RadixError is raised for corrupt nodes or bad keys in a list
  @spec error(atom, any) :: RadixError.t()
  defp error(reason, data),
    do: RadixError.exception(reason, data)

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

  # Leaf helpers
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

  # Tree helpers

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
  # -TODO: validate leaf here and RAISE an exception (otherwise the exception
  # becomes part of the tree ...
  # now Radix.delete({0, 1, 2}, <<1>>) yields FunctionClauseError for List.keydelete ..
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
  defp reducep(tree, acc, fun)
  defp reducep(nil, acc, _fun), do: acc
  defp reducep([], acc, _fun), do: acc
  defp reducep({_, l, r}, acc, fun), do: reducep(r, reducep(l, acc, fun), fun)
  defp reducep([{k, v} | tail], acc, fun), do: reducep(tail, fun.(k, v, acc), fun)
  defp reducep(tree, _acc, _fun), do: raise(error(:badnode, tree))

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

  defp vertex(acc, _parent, {_, nil}, _port), do: acc
  defp vertex(acc, parent, {child, _}, port), do: ["N#{parent}:#{port} -> N#{child};\n" | acc]

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
  def new(elements) when is_list(elements) do
    try do
      Enum.reduce(elements, @empty, fn {k, v}, t when is_bitstring(k) -> put(t, k, v) end)
    rescue
      FunctionClauseError -> raise bad_list(elements)
    end
  end

  def new(elements),
    do: raise(bad_list(elements))

  @doc """
  Fetches the key,value-pair for a specific `key` in the given `tree`.

  Returns `{:ok, {key, value}}` or :error when `key` is not in the `tree`.

  ## Example

      iex> t = new([{<<1>>, 1}, {<<1, 1>>, 2}])
      iex> fetch(t, <<1, 1>>)
      {:ok, {<<1, 1>>, 2}}
      iex>
      iex> fetch(t, <<2>>)
      :error

  """
  @spec fetch(tree, key) :: {:ok, {key, value}} | :error
  def fetch(tree, key) do
    case get(tree, key) do
      {k, v} -> {:ok, {k, v}}
      _ -> :error
    end
  end

  @doc """
  Fetches the key,value-pair for a specific `key` in the given `tree`.

  Returns the `{key, value}`-pair itself, or raises a `KeyError` if `key` is not in the `tree`.

  ## Example

      iex> t = new([{<<1>>, 1}, {<<1, 1>>, 2}])
      iex> fetch!(t, <<1, 1>>)
      {<<1, 1>>, 2}
      iex>
      iex> fetch!(t, <<2>>)
      ** (KeyError) key not found <<0b10>>

  """
  def fetch!(tree, key) do
    case get(tree, key) do
      {k, v} -> {k, v}
      nil -> raise KeyError, "key not found #{inspect(key, base: :binary)}"
    end
  end

  @doc """
  Get the key,value-pair whose key equals the given search `key`.

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
      iex> get(t, <<1, 1, 0::1>>, "oops")
      "oops"

  """
  @spec get(tree, key, any) :: {key, value} | any
  def get(tree, key, default \\ nil)

  def get({0, _, _} = tree, key, default) when is_bitstring(key) do
    kmax = bit_size(key)

    tree
    |> leaf(key, kmax)
    |> keyget(key, kmax) || default
  end

  def get({0, _, _} = _tree, key, _default),
    do: raise(bad_key(key))

  def get(tree, _key, _default),
    do: raise(bad_tree(tree))

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
  def put({0, _, _} = tree, elements) when is_list(elements) do
    try do
      Enum.reduce(elements, tree, fn {k, v}, t when is_bitstring(k) -> put(t, k, v) end)
    rescue
      FunctionClauseError -> raise bad_list(elements)
    end
  end

  def put({0, _, _} = _tree, elements),
    do: raise(bad_list(elements))

  def put(tree, _elements),
    do: raise(bad_tree(tree))

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
  @spec put(tree, key, value) :: tree
  def put({0, _, _} = tree, key, value) when is_bitstring(key),
    do: putp(tree, keypos(tree, key), key, value)

  def put({0, _, _} = _tree, key, _value),
    do: raise(bad_key(key))

  def put(tree, _key, _value),
    do: raise(bad_tree(tree))

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
    do: deletep(tree, key)

  def delete({0, _, _} = _tree, key),
    do: raise(bad_key(key))

  def delete(tree, _key),
    do: raise(bad_tree(tree))

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
  def drop({0, _, _} = tree, keys) when is_list(keys) do
    try do
      Enum.reduce(keys, tree, fn key, tree when is_bitstring(key) -> delete(tree, key) end)
    rescue
      FunctionClauseError -> raise bad_keys(keys)
    end
  end

  def drop({0, _, _} = _tree, keys),
    do: raise(bad_list(keys))

  def drop(tree, _keys),
    do: raise(bad_tree(tree))

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
    do: lookupp(tree, key, bit_size(key))

  def lookup({0, _, _} = _tree, key),
    do: raise(bad_key(key))

  def lookup(tree, _key),
    do: raise(bad_tree(tree))

  @doc """
  Lookup given search `key` in `tree` and update the value of matched key with
  the given function.

  If `key` has a longest prefix match in `tree` then its value is passed to
  `fun` and its result is used as the updated value of the *matching* key. If
  `key` cannot be matched the {`default`, `key`}-pair is inserted in
  the `tree`.

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
  end

  def update(tree, key, _default, fun) when is_bitstring(key) and is_function(fun, 1),
    do: raise(bad_tree(tree))

  def update({0, _, _} = _tree, key, _val, fun) when is_bitstring(key),
    do: raise(bad_fun(fun, 1))

  def update(_tree, key, _default, _fun),
    do: raise(bad_key(key))

  @doc """
  Returns all key,value-pair(s) whose key is a prefix for the given search `key`.

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

  def less({0, _, _} = _tree, key),
    do: raise(bad_key(key))

  def less(tree, _key),
    do: raise(bad_tree(tree))

  @doc """
  Returns all key,value-pair(s) where the given search `key` is a prefix for a stored key.

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

  def more({0, _, _} = _tree, key),
    do: raise(bad_key(key))

  def more(tree, _key),
    do: raise(bad_tree(tree))

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

  def reduce({0, _, _} = _tree, _acc, fun),
    do: raise(bad_fun(fun, 3))

  def reduce(tree, _acc, _fun),
    do: raise(bad_tree(tree))

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

  def to_list(tree),
    do: raise(bad_tree(tree))

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

  def keys(tree),
    do: raise(bad_tree(tree))

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

  def values(tree),
    do: raise(bad_tree(tree))

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
      iex> walk(t, [], f)
      [1, 2, 3, 128]

  """
  @spec walk(tree, acc, (acc, tree | leaf -> acc), atom) :: acc
  def walk(tree, acc, fun, order \\ :inorder)

  def walk({0, _, _} = tree, acc, fun, order) when is_function(fun, 2),
    do: walkp(acc, fun, tree, order)

  def walk({0, _, _} = _tree, _acc, fun, _order),
    do: raise(bad_fun(fun, 2))

  def walk(tree, _acc, _fun, _order),
    do: raise(bad_tree(tree))

  @doc ~S"""
  Given a tree, returns a list of lines describing the tree as a [graphviz](https://graphviz.org/) digraph.

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
      ["digraph Radix {\n  labelloc=\"t\";\n  label=\"example\";\n  rankdir=\"TB\";\n  ranksep=\"0.5 equally\";\n",
        "N4 [label=<\n  <TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\">\n    <TR><TD PORT=\"N4\" BGCOLOR=\"green\">leaf</TD></TR>\n    <TR><TD>128.0/16</TD></TR>\n  </TABLE>\n  >, shape=\"plaintext\"];\n",
        "N2 [label=<\n  <TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\">\n    <TR><TD PORT=\"N2\" BGCOLOR=\"green\">leaf</TD></TR>\n    <TR><TD>1.1.128/17</TD></TR>\n  </TABLE>\n  >, shape=\"plaintext\"];\n",
        "N1 [label=<\n  <TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\">\n    <TR><TD PORT=\"N1\" BGCOLOR=\"green\">leaf</TD></TR>\n    <TR><TD>0.0/16</TD></TR>\n  </TABLE>\n  >, shape=\"plaintext\"];\n",
        "N3:R -> N2;\n",
        "N3:L -> N1;\n",
        "N3 [label=<\n  <TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\">\n    <TR><TD PORT=\"N3\" COLSPAN=\"2\" BGCOLOR=\"yellow\">bit 7</TD></TR>\n    <TR><TD PORT=\"L\">0</TD><TD PORT=\"R\">1</TD></TR>\n  </TABLE>\n>, shape=\"plaintext\"];\n",
        "N5:R -> N4;\n",
        "N5:L -> N3;\n",
        "N5 [label=<\n  <TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\">\n    <TR><TD PORT=\"N5\" COLSPAN=\"2\" BGCOLOR=\"orange\">bit 0</TD></TR>\n    <TR><TD PORT=\"L\">0</TD><TD PORT=\"R\">1</TD></TR>\n  </TABLE>\n>, shape=\"plaintext\"];\n",
        "}"]
      iex> File.write("assets/example.dot", g)
      :ok

   which, after converting with `dot`, yields the following image:

   ![example](assets/example.dot.png)

  """
  @spec dot(tree, keyword()) :: list(String.t())
  def dot(tree, opts \\ [])

  def dot({0, _, _} = tree, opts) do
    tree
    |> annotate()
    |> dotify(opts)
    |> List.flatten()
  end

  def dot(tree, _opts),
    do: raise(bad_tree(tree))
end
