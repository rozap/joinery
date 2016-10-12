defmodule Joinery.Join do
  alias Joinery.Pager


  defp advance([row | _] = rows, join_on) do
    value = Map.get(row, join_on)
    Enum.split_while(rows, fn %{^join_on => rest_value} ->
      value == rest_value
    end)
  end

  # When both subsets are empty, advance both left and right
  defp join_maps([], [], left, right, join_on) do
    {left_subset, left_rest} = advance(left, join_on)
    {right_subset, right_rest} = advance(right, join_on)

    join_maps(left_subset, right_subset, left_rest, right_rest, join_on)
  end

  defp join_maps([], right_subset, [left_head | left_rest], right, join_on) do

    join_maps([left_head], right, left_rest, right, join_on)
  end

  defp join_maps(left_subset, [], left, [right_head | right_rest], join_on) do
    join_maps(left_subset, [right_head], left, right_rest, join_on)
  end

  defp join_maps(left_subset, right_subset, left, right, join_on) do
    left_value = left[join_on]
    right_value = right[join_on]

    if left_value == right_value do

    end

    IO.inspect left
    IO.inspect right
  end



  defp join_maps(left, right, join_on) do
    join_maps([], [], left, right, join_on)
  end



  defp to_maplist(rows) do
    Enum.map(rows, fn row -> Enum.into(row, %{}) end)
  end

  def join(left_pager, right_pager, join_on) do
    with {:ok, left} <- Pager.next(left_pager),
      {:ok, right} <- Pager.next(right_pager) do

      join_maps(
        to_maplist(left),
        to_maplist(right),
        join_on
      )
    end
  end




end