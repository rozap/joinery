defmodule JoinTest do
  use ExUnit.Case
  alias Joinery.Join

  def sort_by_key(rows, key) do
    Enum.sort_by(rows, fn keylist ->
      {_, value} = Enum.find(keylist, fn {a_key, _} -> a_key == key end)
      value
    end)
  end

  test "can do a simple join" do
    left = [
      [{"name", "chris"}, {"emoji", ":dumpsterfire:"}],
      [{"name", "urmi"}, {"emoji", ":confused-yay:"}],
      [{"name", "pete"}, {"emoji", ":elm:"}],
      [{"name", "cate"}, {"emoji", ":cat:"}],
      [{"name", "kaida"}, {"emoji", ":tofu:"}],
      [{"name", "michael"}, {"emoji", ":rainier:"}],
      [{"name", "robert"}, {"emoji", ":haskell:"}]
    ] |> sort_by_key("emoji")


    right = [
      [{"image", "dumpsterfire.png"}, {"emoji", ":dumpsterfire:"}],
      [{"image", "confused_yay.png"}, {"emoji", ":confused-yay:"}],
      [{"image", "elm.png"}, {"emoji", ":elm:"}],
      [{"image", "cat.png"}, {"emoji", ":cat:"}],
      [{"image", "tofu.png"}, {"emoji", ":tofu:"}],
      [{"image", "rainier.png"}, {"emoji", ":rainier:"}],
      [{"image", "haskell.png"}, {"emoji", ":haskell:"}]
    ] |> sort_by_key("emoji")

    Join.join(left, right, "image")
  end
end
