defmodule Joinery.Join do
  alias Joinery.Pager

  defmodule State do
    defstruct l_value: nil,
      r_value: nil,
      l_join_on: nil,
      r_join_on: nil,
      l_subset: [],
      r_subset: [],
      l_rows: [],
      r_rows: [],
      l_pager: :done,
      r_pager: :done
  end

  defp advance(value, subset, [], pager, join_on) when pager != :done do
    case Pager.next(pager) do
      {:ok, page} ->
        mappy_page = Enum.map(page, fn row -> Enum.into(row, %{}) end)
        advance(value, subset, mappy_page, pager, join_on)
      :done ->
        advance(value, subset, [], :done, join_on)
    end
  end

  defp advance(:empty, [row | _] = subset, rows, pager, join_on) do
    value = Map.get(row, join_on)
    advance(value, subset, rows, pager, join_on)
  end

  defp advance(:empty, [], [row | _] = rows, pager, join_on) do
    value = Map.get(row, join_on)
    advance(value, [], rows, pager, join_on)
  end

  defp advance(value, subset, [], :done, _) do
    {value, subset, [], :done}
  end

  defp advance(value, subset, rows, pager, join_on) when length(rows) > 0 do
    {new_subset, new_rows, _} = Enum.reduce(
      rows,
      {subset, [], true},
      fn
        row, {matched, unmatched, false} ->
          {matched, [row | unmatched], false}
        %{^join_on => rest_value} = row, {matched, unmatched, is_matching} ->
          if rest_value == value do
            {[row | matched], unmatched, true}
          else
            {matched, [row | unmatched], false}
          end
      end
    )

    new_subset = Enum.reverse(new_subset)
    new_rows = Enum.reverse(new_rows)


    if length(new_rows) == 0 do
      advance(value, new_subset, new_rows, pager, join_on)
    else
      {value, new_subset, new_rows, pager}
    end
  end

  defp advance(value, subset, rows, pager, _) when length(subset) > 0 do
    {value, subset, rows, pager}
  end

  def advance(rows, pager, join_on) do
    advance(:empty, [], rows, pager, join_on)
  end

  defp cart_product(left, right) do
    Enum.map(left, fn l_row ->
      Enum.flat_map(right, fn r_row ->
        Map.merge(l_row, r_row)
      end)
    end)
  end

  # When right_subset or left_subset are empty and when there are no
  # more rows that we can possibly fetch out of anywhere, we're done
  defp do_join(%State{l_subset: ls, r_subset: rs, l_rows: [], r_rows: [], l_pager: :done, r_pager: :done})
    when (ls == []) or (rs == []) do
    []
  end

  # When the join value is the same for both subsets, we execute the join
  # on the subsets
  defp do_join(%State{l_value: value, r_value: value} = state) do
    product = cart_product(state.l_subset, state.r_subset)

    {l_value, l_subset, l_rows, l_pager} = advance(
      state.l_rows,
      state.l_pager,
      state.l_join_on
    )
    {r_value, r_subset, r_rows, r_pager} = advance(
      state.r_rows,
      state.r_pager,
      state.r_join_on
    )

    new_state = struct(state,
      l_value: l_value,
      r_value: r_value,
      l_subset: l_subset,
      r_subset: r_subset,
      l_rows: l_rows,
      r_rows: r_rows,
      l_pager: l_pager,
      r_pager: r_pager
    )

    # Naughty - fix this by making it lazy or an iolist
    product ++ do_join(new_state)
  end

  # When the left value'd subset is less than that of the right, we advance
  # the left subset, filling it with new rows
  defp do_join(%State{l_value: l_value, r_value: r_value} = state)
    when l_value < r_value do
      {l_value, l_subset, l_rows, l_pager} = advance(
        state.l_rows,
        state.l_pager,
        state.l_join_on
      )

      new_state = struct(state,
        l_value: l_value,
        l_subset: l_subset,
        l_rows: l_rows,
        l_pager: l_pager,
      )

      do_join(new_state)
  end

  # When the right value'd subset is less than the left, we advance
  # the right subset, filling it with new rows
  defp do_join(%State{l_value: l_value, r_value: r_value} = state)
    when l_value > r_value do
      {r_value, r_subset, r_rows, r_pager} = advance(
        state.r_rows,
        state.r_pager,
        state.r_join_on
      )

      new_state = struct(state,
        r_value: r_value,
        r_subset: r_subset,
        r_rows: r_rows,
        r_pager: r_pager
      )

      do_join(new_state)
  end

  def join(l_pager, r_pager, l_join_on, r_join_on) do
    {l_value, l_subset, l_rows, l_pager} = advance([], l_pager, l_join_on)
    {r_value, r_subset, r_rows, r_pager} = advance([], r_pager, r_join_on)

    do_join(%State{
      l_value: l_value,
      r_value: r_value,
      l_join_on: l_join_on,
      r_join_on: r_join_on,
      l_subset: l_subset,
      r_subset: r_subset,
      l_rows: l_rows,
      r_rows: r_rows,
      l_pager: l_pager,
      r_pager: r_pager,
    })
  end

end