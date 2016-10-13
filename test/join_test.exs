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

  def loop(rows) do
    receive do
      {:fetch_next, sender_pid} ->
        {rows, rest} = Enum.split(rows, 3)
        response = {:ok, rows}
        send sender_pid, {:fetched, response}
        loop(rest)
    end
  end
end


defmodule JoinTest do
  use ExUnit.Case
  alias Joinery.Join

  test "can do an inner join" do
    left_pager = FastPager.start("emoji", [
      [{"name", "chris"}, {"emoji", ":dumpsterfire:"}],
      [{"name", "urmi"}, {"emoji", ":aussie:"}],
      [{"name", "pete"}, {"emoji", ":elm:"}],
      [{"name", "cate"}, {"emoji", ":cat:"}],
      [{"name", "kaida"}, {"emoji", ":tofu:"}],
      [{"name", "michael"}, {"emoji", ":rainier:"}],
      [{"name", "robert"}, {"emoji", ":tofu:"}]
    ])

    right_pager = FastPager.start("emoji", [
      [{"image", "dumpsterfire.png"}, {"emoji", ":dumpsterfire:"}],
      [{"image", "confused_yay.png"}, {"emoji", ":confused-yay:"}],
      [{"image", "elm.png"}, {"emoji", ":elm:"}],
      [{"image", "cat.png"}, {"emoji", ":cat:"}],
      [{"image", "aaa.png"}, {"emoji", ":aaa:"}],
      [{"image", "tofu.png"}, {"emoji", ":tofu:"}],
      [{"image", "aussie.png"}, {"emoji", ":aussie:"}],
      [{"image", "rainier.png"}, {"emoji", ":rainier:"}],
      [{"image", "zzz.png"}, {"emoji", ":zzz:"}],
    ])

    joined = Join.join(left_pager, right_pager, "emoji", "emoji")
    |> IO.inspect

    assert joined == [
      [{"emoji", ":aussie:"}, {"image", "aussie.png"}, {"name", "urmi"}],
      [{"emoji", ":cat:"}, {"image", "cat.png"}, {"name", "cate"}],
      [{"emoji", ":dumpsterfire:"}, {"image", "dumpsterfire.png"}, {"name", "chris"}],
      [{"emoji", ":elm:"}, {"image", "elm.png"}, {"name", "pete"}],
      [{"emoji", ":rainier:"}, {"image", "rainier.png"}, {"name", "michael"}],
      [{"emoji", ":tofu:"}, {"image", "tofu.png"}, {"name", "kaida"}],
      [{"emoji", ":tofu:"}, {"image", "tofu.png"}, {"name", "robert"}]
    ]
  end


  test "can do an inner join on different keys" do
    left_pager = FastPager.start("something", [
      [{"name", "chris"}, {"something", ":dumpsterfire:"}],
      [{"name", "urmi"}, {"something", ":aussie:"}],
      [{"name", "pete"}, {"something", ":elm:"}],
      [{"name", "cate"}, {"something", ":cat:"}],
      [{"name", "kaida"}, {"something", ":tofu:"}],
      [{"name", "michael"}, {"something", ":rainier:"}],
      [{"name", "robert"}, {"something", ":tofu:"}]
    ])

    right_pager = FastPager.start("emoji", [
      [{"image", "dumpsterfire.png"}, {"emoji", ":dumpsterfire:"}],
      [{"image", "confused_yay.png"}, {"emoji", ":confused-yay:"}],
      [{"image", "elm.png"}, {"emoji", ":elm:"}],
      [{"image", "cat.png"}, {"emoji", ":cat:"}],
      [{"image", "aaa.png"}, {"emoji", ":aaa:"}],
      [{"image", "tofu.png"}, {"emoji", ":tofu:"}],
      [{"image", "aussie.png"}, {"emoji", ":aussie:"}],
      [{"image", "rainier.png"}, {"emoji", ":rainier:"}],
      [{"image", "zzz.png"}, {"emoji", ":zzz:"}],
    ])

    joined = Join.join(left_pager, right_pager, "something", "emoji")

    assert joined == [
      [{"emoji", ":aussie:"}, {"image", "aussie.png"}, {"name", "urmi"}, {"something", ":aussie:"}],
      [{"emoji", ":cat:"}, {"image", "cat.png"}, {"name", "cate"}, {"something", ":cat:"}],
      [{"emoji", ":dumpsterfire:"}, {"image", "dumpsterfire.png"}, {"name", "chris"}, {"something", ":dumpsterfire:"}],
      [{"emoji", ":elm:"}, {"image", "elm.png"}, {"name", "pete"}, {"something", ":elm:"}],
      [{"emoji", ":rainier:"}, {"image", "rainier.png"}, {"name", "michael"}, {"something", ":rainier:"}],
      [{"emoji", ":tofu:"}, {"image", "tofu.png"}, {"name", "kaida"}, {"something", ":tofu:"}],
      [{"emoji", ":tofu:"}, {"image", "tofu.png"}, {"name", "robert"}, {"something", ":tofu:"}]
    ]
  end
end
