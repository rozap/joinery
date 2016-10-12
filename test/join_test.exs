defmodule FastPager do
  def start(sort_key, rows) do
    sorted_rows = Enum.sort_by(rows, fn keylist ->
      {_, value} = Enum.find(keylist, fn {a_key, _} -> a_key == sort_key end)
      value
    end)

    spawn_link(
      FastPager,
      :loop,
      [sorted_rows]
    )
  end

  def loop([]) do
    receive do
      {:fetch_next, sender_pid} ->
        send sender_pid, :done
    end
  end

  def loop([row | rest]) do
    receive do
      {:fetch_next, sender_pid} ->
        response = {:ok, [row]}
        IO.puts "Sending #{inspect response}"
        send sender_pid, {:fetched, response}
        loop(rest)
    end
  end
end


defmodule JoinTest do
  use ExUnit.Case
  alias Joinery.Join

  test "can do a simple join" do
    left_pager = FastPager.start("emoji", [
      # [{"name", "chris"}, {"emoji", ":dumpsterfire:"}],
      # [{"name", "urmi"}, {"emoji", ":confused-yay:"}],
      # [{"name", "pete"}, {"emoji", ":elm:"}],
      # [{"name", "cate"}, {"emoji", ":cat:"}],
      [{"name", "kaida"}, {"emoji", ":tofu:"}],
      [{"name", "michael"}, {"emoji", ":rainier:"}],
      [{"name", "robert"}, {"emoji", ":tofu:"}]
    ])

    right_pager = FastPager.start("emoji", [
      # [{"image", "dumpsterfire.png"}, {"emoji", ":dumpsterfire:"}],
      # [{"image", "confused_yay.png"}, {"emoji", ":confused-yay:"}],
      # [{"image", "elm.png"}, {"emoji", ":elm:"}],
      # [{"image", "cat.png"}, {"emoji", ":cat:"}],
      [{"image", "tofu.png"}, {"emoji", ":tofu:"}],
      [{"image", "rainier.png"}, {"emoji", ":rainier:"}]
    ])


    Join.join(left_pager, right_pager, "emoji")
  end
end
