defmodule Joinery.Pager do
  import Exsoda.Reader
  require Logger

  def start(fourfour, order, page_size \\ 100) do
    count_response = query(fourfour)
    |> select(["count(*)"])
    |> run

    with {:ok, stream} <- count_response do
      [{"count", c}] = List.first(Enum.into(stream, []))
      row_count = String.to_integer(c)

      Logger.info("Expecting to find #{row_count} in #{fourfour}")

      # Start a new process
      pid = spawn_link(Joinery.Pager, :handle_fetches, [fourfour, order, row_count, page_size, 0])
      {:ok, pid}
    end
  end

  def handle_fetches(fourfour, _, row_count, page_size, current_page) when current_page * page_size >= row_count do
    IO.puts "#{inspect self} Pager for #{fourfour} has been exhausted, exiting..."
    receive do
      {:fetch_next, sender_pid} ->
        send sender_pid, :done
    end
  end

  def handle_fetches(fourfour, order, row_count, page_size, current_page) do
    receive do
      {:fetch_next, sender_pid} ->
        Logger.info("#{inspect self } is fetching next for #{fourfour}")
        response = query(fourfour)
        |> order(order)
        |> offset(page_size * current_page)
        |> limit(page_size)
        |> run

        result = case response do
          {:ok, stream} -> {:ok, Enum.into(stream, [])}
          {:error, _} = e -> e
        end

        # Send the result of the page to the process that asked for it
        send sender_pid, {:fetched, result}

        # Now we recursively call ourselves with the incremented page
        new_page = current_page + 1
        handle_fetches(fourfour, order, row_count, page_size, new_page)
      other ->
        IO.puts("Pager got an unknown message #{inspect other}")
        # We don't know what to do with that message, so the state won't change
        handle_fetches(fourfour, order, row_count, page_size, current_page)
    end
  end

  def next(pid) do
    IO.puts "Fetch next from #{inspect pid}"
    send pid, {:fetch_next, self()}

    receive do
      {:fetched, result} -> result
      :done -> :done
    after
      5_000 -> {:error, :timeout}
    end
  end
end