defmodule Joinery.Router do
  use Plug.Router
  require Logger

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

  defp display_name_to_field_name(four_four, display_name) do
    query = Exsoda.Reader.query(four_four)
    with {:ok, view} <- Exsoda.Reader.get_view(query) do
      found = view
      |> Map.get("columns", [])
      |> Enum.find_value(fn col ->
        if Map.get(col, "name") == display_name do
          {:ok, Map.get(col, "fieldName")}
        else
          false
        end
      end)

      unless found do
        {:error, "Didn't find a fieldName matching #{display_name}"}
      else
        found
      end
    end
  end

  get "/join/:left/:right" do
    result = with {:ok, left_ff, left_j} <- to_fourfour_join(left),
      {:ok, right_ff, right_j} <- to_fourfour_join(right),
      {:ok, left_field_name} <- display_name_to_field_name(left_ff, left_j),
      {:ok, right_field_name} <- display_name_to_field_name(right_ff, right_j) do

      Logger.info("Planning to join #{left_ff}.#{left_j} (#{left_field_name}) to #{right_ff}.#{right_j} (#{right_field_name})")

      {:ok, left} = Joinery.Pager.start(left_ff, left_field_name)
      {:ok, right} = Joinery.Pager.start(right_ff, right_field_name)

      response = Joinery.Join.join(left, right, left_j, right_j)
      # Since our join/4 function gives back keyword lists, we
      # need to change those keyword lists into Maps.
      # Enum.into(a_keylist, %{}) converts a keylist into a map
      |> Enum.map(fn keylist -> Enum.into(keylist, %{}) end)
      # Encode our list of maps as json
      |> Poison.encode!

      # Write all of them to the connection, give back a new connection
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