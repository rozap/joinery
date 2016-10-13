defmodule Joinery.Router do
  use Plug.Router
  require Logger
  alias Joinery.{Join, Pager}

  plug :match
  plug :dispatch

  get "/hello" do
    send_resp(conn, 200, "world")
  end


  defp to_fourfour_join(url) do
    case String.split(url, ".") do
      [ff, j] -> {:ok, ff, j}
      _ -> {:error, "Don't know how to do that"}
    end
  end

  get "/join/:left/:right" do
    result = with {:ok, left_ff, left_j} <- to_fourfour_join(left),
      {:ok, right_ff, right_j} <- to_fourfour_join(right) do

      Logger.info("Planning to join #{left_ff}.#{left_j} to #{right_ff}.#{right_j}")

      {:ok, left} = Pager.start(left_ff, "zip_code")
      {:ok, right} = Pager.start(right_ff, "zip_code")

      joined = Join.join(left, right, left_j, right_j)

      Logger.info("Joined #{length joined} rows")

      response = joined
      |> Enum.map(fn row -> Enum.into(row, %{}) end)
      |> Poison.encode!
      send_resp(conn, 200, response)
    end

    with {:error, reason} <- result do
      send_resp(conn, 400, reason)
    end
  end

  match _ do
    send_resp(conn, 404, "idk")
  end
end