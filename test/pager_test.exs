defmodule PagerTest do
  use ExUnit.Case
  alias Joinery.Pager

  test "can get the first page" do
    {:ok, pager_pid} = Pager.start("hcnj-rei3", "zip_code", 5)

    {:ok, rows} = Pager.next(pager_pid)
    assert length(rows) == 5
  end

  test "can get the second page" do
    {:ok, lil_pager} = Pager.start("hcnj-rei3", "zip_code", 5)

    {:ok, first} = Pager.next(lil_pager)
    {:ok, second} = Pager.next(lil_pager)

    {:ok, big_pager} = Pager.start("hcnj-rei3", "zip_code", 10)
    {:ok, all} = Pager.next(big_pager)


    assert (first ++ second) == all
  end
end
