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
    {:ok, %{}}
  end

  def compile(file_name, compile_in, opts) do
    GenServer.call(__MODULE__, {:compile, file_name, compile_in, opts})
  end

  def handle_call({:compile, file_name, compile_in, opts}, _from, state) do
    if need_recompile?(state, file_name) do
      source = compile_coffee(file_name, compile_in, opts)
      state = Map.put_new(state, file_name, {source, file_mtime(file_name)})
    else
      {source, _} = Map.get(state, file_name)
    end
    {:reply, source, state}
  end

  defp need_recompile?(state, file_name) do
    case Map.fetch(state, file_name) do
      {:ok, {_, last_mtime}} ->
        Date.diff(last_mtime, file_mtime(file_name), :secs) > 0
      _ -> true
    end
  end

  defp compile_coffee(file_name, false, opts) do
    args = ["-p", file_name]
    if Keyword.get(opts, :bare) do
      args = ["-b" | args]
    end
    Logger.info "Compiling #{file_name}"
    {source, 0} = System.cmd @coffee_cmd, args
    source
  end

  defp compile_coffee(file_name, compile_in, opts) do
    timestamp = file_name |> file_mtime |> Date.to_secs
    cache_file_name = Path.split(file_name) |> Enum.join("_") |> Path.basename(".coffee")
    cache_file_name = "#{timestamp}_#{cache_file_name}.js"
    cache_file = Path.join(compile_in, cache_file_name)
    if File.exists?(cache_file) do
      Logger.info "Reading #{file_name} from cache"
      File.read!(cache_file)
    else
      source = compile_coffee(file_name, false, opts)
      Logger.info "Saving #{file_name} to #{cache_file}"
      File.write!(cache_file, source)
      source
    end
  end

  defp file_mtime(file_name) do
    file_info(mtime: mtime) = read_file_info(file_name)
    Date.from(mtime)
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
