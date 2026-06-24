defmodule Waiter do
  use GenServer
  
  def start_link(id) do
    GenServer.start_link(__MODULE__, :ok, name: {:global, {:waiter, id}})
  end

  def get_forks(id) do
    GenServer.call({:global, {:waiter, id}}, :get_forks, :infinity)
  end

  def rel_forks(id) do
    GenServer.cast({:global, {:waiter, id}}, :rel_forks)
  end

  @impl true
  def init(:ok) do
    {:ok, :available} # O estado inicial do garçom é disponível
  end

  @impl true
  def handle_call(:get_forks, _from, :available) do
    {:reply, :ok, :busy}
  end

  @impl true
  def handle_call(:get_forks, from, :busy) do
    {:noreply, {:busy_waiting, from}}
  end

  @impl true
  def handle_cast(:rel_forks, :busy) do
    {:noreply, :available}
  end

  @impl true
  def handle_cast(:rel_forks, {:busy_waiting, pending_philosopher}) do
    GenServer.reply(pending_philosopher, :ok)
    {:noreply, :busy}
  end
end

defmodule Philosopher do
  def start_link(id) do
    # Cria um processo isolado que rodará o loop infinito do filósofo
    spawn_link(fn -> p_loop(id) end)
  end

  def p_loop(id) do
    # Define a ordem dos garçons para evitar deadlock
    {first, second} = if id == 4, do: {0, 4}, else: {id, id + 1}

    #Pensa por um tempo aleatório
    IO.puts(" Filosofo #{id} esta pensando...")
    :timer.sleep(:rand.uniform(1500))

    #Tenta pegar os garfos (Bloqueante)
    IO.puts(" Filosofo #{id} tentando pegar garfo do Garcom #{first}...")
    Waiter.get_forks(first)
    
    IO.puts(" Filosofo #{id} pegou o primeiro garfo. Tentando garfo do Garcom #{second}...")
    Waiter.get_forks(second)

    #Come por um tempo aleatório
    IO.puts(" Filosofo #{id} esta COMENDO")
    :timer.sleep(:rand.uniform(1500))

    #Libera os garfos (Assíncrono)
    IO.puts(" Filosofo #{id} terminou de comer. Liberando garcons #{first} e #{second}.")
    Waiter.rel_forks(first)
    Waiter.rel_forks(second)

    # Repete
    p_loop(id)
  end
end

# --- Módulo Inicializador ---
defmodule Main do
  def run do
    IO.puts(" Iniciando o Jantar dos Filosofos ")

    #Inicia os 5 Garçons (Waiters)
    Enum.each(0..4, fn id -> 
      Waiter.start_link(id) 
    end)

    #Inicia os 5 Filósofos
    Enum.each(0..4, fn id -> 
      Philosopher.start_link(id) 
    end)

    # Mantém o script principal vivo para observar a interação dos processos
    :timer.sleep(:infinity)
  end
end

Main.run()
