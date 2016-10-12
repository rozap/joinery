defmodule Joinery.Join do
  alias Joinery.Pager


  defp advance(value, subset, rows, pager, join_on, false) when length(subset) > 0 do
    {value, subset, rows}
  end

  defp advance(value, subset, [], pager, join_on, true) do
    case Pager.next(pager) do
      {:ok, page} ->
        mappy_page = Enum.map(page, fn row -> Enum.into(row, %{}) end)
        # IO.puts "Got page #{inspect mappy_page}"
        advance(value, subset, mappy_page, pager, join_on, true)
      :done ->
        advance(value, subset, [], pager, join_on, false)
    end
  end

  defp advance(:empty, [row | _] = subset, rows, pager, join_on, has_more) do
    value = Map.get(row, join_on)
    advance(value, subset, rows, pager, join_on, has_more)
  end

  defp advance(:empty, [], [row | _] = rows, pager, join_on, has_more) do
    value = Map.get(row, join_on)
    advance(value, [], rows, pager, join_on, has_more)
  end

  defp advance(value, subset, rows, pager, join_on, has_more) do
    {new_subset, new_rows} = Enum.reduce_while(
      rows,
      {subset, []},
      fn %{^join_on => rest_value} = row, {subset, rows} ->
        if rest_value == value do
          {:cont, {[row | subset], rows}}
        else
          {:halt, {subset, rows}}
        end
      end
    )

    # IO.puts " joining on #{value} >> #{inspect new_subset} #{inspect new_rows}"
    advance(value, new_subset, new_rows, pager, join_on, has_more)
  end

  def advance(rows, pager, join_on) do
    IO.puts "Advance call #{inspect rows}"
    advance(:empty, [], rows, pager, join_on, true)
  end

  defp cart_product(left, right) do
    Enum.flat_map(left, fn l_row ->
      Enum.flat_map(right, fn r_row ->
        Map.merge(l_row, r_row)
      end)
    end)
  end

  defp do_join(_, _, left_subset, right_subset, _, _, _, _, _)
    when ((length(left_subset) == 0) or (length(right_subset) == 0)) do
    IO.puts "Done!"
  end

  # # When both subsets are empty, advance both left and right
  defp do_join(value, value, left_subset, right_subset, left, right, l_pager, r_pager, join_on) do
    product = cart_product(left_subset, right_subset)

    IO.puts "Product is #{inspect product}"

    {new_l_value, new_left_subset, left_rest}    = advance(left, l_pager, join_on)
    {new_r_value, new_right_subset, right_rest}  = advance(right, r_pager, join_on)

    do_join(
      new_l_value, new_r_value,
      new_left_subset, new_right_subset,
      left_rest, right_rest,
      l_pager, r_pager,
      join_on
    )
  end

  defp do_join(l_value, r_value, left_subset, right_subset, left, right, l_pager, r_pager, join_on)
    when l_value < r_value do
      {new_l_value, new_left_subset, left_rest} = advance(left, l_pager, join_on)

      do_join(
        new_l_value, r_value,
        new_left_subset, right_subset,
        left_rest, right,
        l_pager, r_pager,
        join_on
      )
  end

  defp do_join(l_value, r_value, left_subset, right_subset, left, right, l_pager, r_pager, join_on)
    when l_value > r_value do
      {new_r_value, new_right_subset, right_rest} = advance(right, r_pager, join_on)

      do_join(
        l_value, new_r_value,
        left_subset, new_right_subset,
        left, right_rest,
        l_pager, r_pager,
        join_on
      )
  end

  def join(l_pager, r_pager, join_on) do
    {l_value, left_subset, left_rest} = advance([], l_pager, join_on)
    {r_value, right_subset, right_rest} = advance([], r_pager, join_on)

    do_join(
      l_value, r_value,
      left_subset, right_subset,
      left_rest, right_rest,
      l_pager,
      r_pager,
      join_on
    )
  end

end