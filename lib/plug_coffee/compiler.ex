defmodule PlugCoffee.Compiler do
  use GenServer
  use Timex
  require Logger

  require Record
  Record.defrecordp :file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl")

  @coffee_cmd "coffee"

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Application.get_env(:plug_coffee, :db_file, "tmp/coffee_cache.db")
    |> check_filename!
    |> String.to_char_list
    |> open_db_file
  end

  defp open_db_file(name) do
    case :dets.open_file(name, type: :set) do
      {:ok, name} = ret -> ret
      {:error, reason} -> {:stop, reason}
    end
  end

  defp check_filename!(name) do
    dir_name = Path.dirname(name)
    unless File.dir?(dir_name) do
      :ok = File.mkdir_p dir_name
    end
    name
  end

  def compile(file_name, opts) do
    GenServer.call(__MODULE__, {:compile, file_name, opts})
  end

  def handle_call({:compile, file_name, opts}, _from, state) do
    {:reply,
      case lookup_file(file_name, state) do
        {:ok, source} ->
          Logger.info "Found cached version of #{file_name}"
          source
        _ ->
          Logger.info "Compiling #{file_name}"
          source = compile_coffee(file_name, opts)
          :ok = :dets.match_delete(state, {{file_name, :_}, :_})
          :ok = :dets.insert(state, {{file_name, file_mtime(file_name)}, source})
          source
      end,
      state}
  end

  def terminate(reason, state) do
    case :dets.close(state) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error "Failed to close DETS database: #{reason}"
        :ok
    end
  end

  defp lookup_file(file_name, state) do
    key = {file_name, file_mtime(file_name)}
    case :dets.lookup(state, key) do
      [{^key, content} | _] -> {:ok, content}
      _ -> :error
    end
  end

  defp compile_coffee(file_name, opts) do
    args = ["-p", file_name]
    if Keyword.get(opts, :bare) do
      args = ["-b" | args]
    end
    {source, 0} = System.cmd @coffee_cmd, args
    source
  end

  defp file_mtime(file_name) do
    file_info(mtime: mtime) = read_file_info(file_name)
    mtime
  end

  defp read_file_info(file) do
    case :file.read_file_info(file) do
      {:ok, info} ->
        info
      _ ->
        nil
    end
  end
end
