defmodule PlugCoffee.Plug do
  @behaviour Plug
  @allowed_methods ~w(HEAD GET)

  @cache_control_ttl_default 86400

  import Plug.Conn
  alias Plug.Conn
  use Timex

  require Record
  Record.defrecordp :file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl")

  defmodule InvalidPathError do
    defexception message: "invalid path for static asset", plug_status: 400
  end

  def init(opts) do
    root = Keyword.get(opts, :root)
    unless File.exists?(root) do
      raise InvalidPathError, message: "Root folder doesn't exist"
    end
    opts
  end

  def call(conn = %Conn{method: method}, opts)
  when method in @allowed_methods do

    path = ["" | conn.path_info] |> Enum.join("/")
    urls = Keyword.get(opts, :urls, ["/javascripts"])
    cond do
      not own_path?(urls, path) ->
        conn
      String.contains?(path, "..") ->
        conn
        |> send_err_resp(403, "Forbidden\n")
        |> halt
      true ->
        do_path conn, path, opts
    end
  end
  def call(conn, _opts), do: conn

  defp do_path(conn, path, opts) do
    root = Keyword.get(opts, :root)
    compile_without_closure = Keyword.get(opts, :bare, false)

    coffee_file = path
                  |> String.replace(~r(\.js$), ".coffee")
                  |> String.replace(~r(^/), "")
    desired_path = Path.join(root, coffee_file)
    if File.exists?(desired_path) do
      file_info(mtime: mtime) = read_file_info(desired_path)
      mtime = Date.from(mtime)
      if is_modified_since(conn, mtime) do
        source = PlugCoffee.Compiler.compile(desired_path, bare: compile_without_closure)
        conn
        |> put_resp_header("content-type", "application/javascript")
        |> put_resp_header("last-modified", format_date(mtime))
        |> send_resp(200, source)
        |> halt
      else
        conn
        |> send_err_resp(304, "Not modified")
        |> halt
      end
    else
      conn
    end
  end

  defp send_err_resp(conn, code, text) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(code, text)
  end

  defp read_file_info(file) do
    case :file.read_file_info(file) do
      {:ok, info} ->
        info
      _ ->
        nil
    end
  end

  @if_modified_format "%a, %d %b %Y %T %Z"

  defp is_modified_since(conn, last_modified) do
    cache_time = Conn.get_req_header(conn, "if-modified-since") |> List.first
    if cache_time do
      case Timex.parse(cache_time, @if_modified_format, :strftime) do
        {:ok, cache_time} ->
          Date.diff(cache_time, last_modified, :secs) > 0
          _ -> true
      end
    else
      true
    end
  end

  defp format_date(date) do
    {:ok, result} = Timex.format(date, @if_modified_format, :strftime)
    result
  end

  defp own_path?(urls, path) do
    Enum.any? urls, &(String.contains?(path, &1))
  end
end
