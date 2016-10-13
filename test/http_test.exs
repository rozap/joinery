defmodule HttpTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias Joinery.Router

  @opts Router.init([])

  test "returns hello world" do
    conn = conn(:get, "/hello")

    # Invoke the plug
    conn = Router.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "world"
  end

end