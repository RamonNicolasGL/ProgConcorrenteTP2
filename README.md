# ProgConcorrenteTP2

# O Jantar dos Filósofos Distribuído em Elixir
<img width="262" height="202" alt="image" src="https://github.com/user-attachments/assets/126d4686-de1a-4bb6-9a33-a4dd0c2dbab9" />

Este projeto apresenta uma implementação do clássico problema de concorrência do **Jantar dos Filósofos** utilizando a linguagem **Elixir**. O objetivo deste código é servir como estudo de caso para soluções distribuídas baseadas em servidores replicados/independentes (`replicated servers`) e troca de mensagens.

A implementação adota um modelo de concorrência tradicional baseado em processos e operações bloqueantes para o **Modelo de Atores** nativo da máquina virtual do Erlang (BEAM).

O código do livro *Foundations of Multithreaded, Parallel, and Distributed Programming* - Gregory R. Andrews; **capítulo 9, seção 9.7, figura 9.20** foi tomado como base para a implementação.

---

## 📌 Contextualização do Problema

O Jantar dos Filósofos ilustra os desafios da alocação de recursos compartilhados em sistemas concorrentes. Cinco filósofos sentam-se à mesa para pensar e comer. Para comer, cada filósofo precisa de dois garfos (o da sua esquerda e o da sua direita). No entanto, existem apenas 5 garfos disponíveis.

### Desafios Resolvidos:
1. **Exclusão Mútua:** Dois filósofos vizinhos não podem comer ao mesmo tempo porque compartilham o mesmo garfo (gerenciado por um processo `Waiter`).
2. **Prevenção de Deadlock:** Se todos os filósofos pegassem o garfo esquerdo simultaneamente, o sistema travaria. A solução implementa uma **estratégia assimétrica** no quinto filósofo (`id = 4`), que inverte a ordem de requisição dos garfos, quebrando o ciclo de dependência.

---

## 🏗️ Arquitetura e Paradigma em Elixir

A solução utiliza o **Modelo de Atores**, onde cada entidade independente é um processo isolado que se comunica exclusivamente por troca de mensagens assíncronas ou síncronas.

### Componentes:

* **`Waiter` (Garçom / Servidor Replicado):** Implementado como um `GenServer`. Existem 5 instâncias independentes rodando em paralelo. Cada `Waiter` gerencia o estado de disponibilidade de um garfo específico (`:available` ou `:busy`). Ele gerencia nativamente a fila de filósofos que estão aguardando o recurso ser liberado.
* **`Philosopher` (Filósofo / Cliente Concorrente):** Implementado como um processo autônomo através de `spawn_link`. Ele executa um loop infinito (via recursão de cauda) alternando entre os estados de *Pensar*, *Requisitar Recursos (Bloqueante)*, *Comer* e *Liberar Recursos (Assíncrono)*.

---

## 🧬 Mapeamento do Código Original para Elixir

A tabela abaixo demonstra como o paradigma de comunicação do código original presente no livro foi mapeado para as construções nativas do Elixir:

| Conceito Original | Implementação em Elixir | Explicação |
| :--- | :--- | :--- |
| `module Waiter[5]` | `Enum.each(0..4, ...)` | Criação de 5 processos `GenServer` independentes na memória. |
| `receive getforks()` | `handle_call(:get_forks, ...)` | Requisição síncrona. Se o garfo estiver ocupado, o servidor retém a resposta (`{:noreply, ...}`), bloqueando o cliente. |
| `receive relforks()` | `handle_cast(:rel_forks, ...)` | Mensagem assíncrona. O filósofo devolve o garfo e continua sua execução imediatamente. |
| `call Waiter[i].getforks()` | `GenServer.call({:global, ...})` | Chamada síncrona que pausa o processo do filósofo até obter o recurso. |
| `send Waiter[i].relforks()` | `GenServer.cast({:global, ...})` | Envio assíncrono de mensagem para o servidor. |
| `while (true)` | Encadeamento Recursivo (`p_loop/1`) | Loops infinitos em Elixir são otimizados pela BEAM através de funções que chamam a si mesmas no final (Tail Call Optimization), garantindo consumo zero de pilha de memória adicional. |

### O Fator Distribuído (`{:global, ...}`)
Os servidores `Waiter` são registrados utilizando a tupla `{:global, {:waiter, id}}`. Isso significa que o catálogo de processos é gerenciado globalmente pela rede da Erlang VM. Se este código for executado em um cluster de máquinas conectadas na mesma rede física, os filósofos de um nó conseguirão localizar e bloquear os garçons localizados em outros nós de maneira totalmente transparente.

---

## 🔍 Análise Detalhada do Código Elixir (Linha por Linha)

Abaixo encontra-se a decomposição técnica de como as regras de negócio e primitivas distribuídas do livro do Andrews foram traduzidas para a sintaxe do Elixir.

### 1. Módulo `Waiter` (O Garçom / Servidor Replicado)

Este módulo corresponde inteiramente ao `module Waiter[5]` do código original. Ele gerencia o estado de um único garfo de forma isolada.

#### A. Interface do Cliente (API Pública)
*Estas funções rodam no contexto do processo do Filósofo, servindo como portas de comunicação.*

* `defmodule Waiter do` / `use GenServer`: Define o escopo do módulo e injeta o comportamento padrão de um servidor genérico OTP. Isso automatiza o gerenciamento assíncrono de caixas de entrada (*mailboxes*).
* `def start_link(id) do`: Define o construtor do processo do garçom.
* `name: {:global, {:waiter, id}}`: **(Mapeamento do índice `Waiter[i]`)** Registra cada servidor sob um alias global na rede da máquina virtual, permitindo escalabilidade transparente entre nós de rede distintos.
* `def get_forks(id) do`: **(Mapeamento de `call Waiter[i].getforks()`)** Dispara uma chamada síncrona através de `GenServer.call/3`. O átomo `:infinity` assegura que o processo do filósofo aceite ficar suspenso na fila o tempo necessário sem estourar o tempo limite (*timeout*).
* `def rel_forks(id) do`: **(Mapeamento de `send Waiter[i].relforks()`)** Dispara uma chamada assíncrona usando `GenServer.cast/2`, permitindo que o filósofo devolva o recurso e volte a pensar sem precisar aguardar um retorno.

#### B. Callbacks Internos de Estado
*Estas funções rodam sob o processo exclusivo de cada Garçom e representam o bloco `while(true) { receive... }` original.*

* `def init(:ok) do`: Inicializa o ciclo de vida do servidor, definindo o estado interno original como o átomo `:available` (livre).
* `def handle_call(:get_forks, _from, :available)`: **(Mapeamento de `receive getforks()` com garfo vago)** Se o recurso está livre, o padrão casa aqui. O retorno `{:reply, :ok, :busy}` envia o sinal de liberação `:ok` ao filósofo e altera o estado interno daquele garçom para `:busy`.
* `def handle_call(:get_forks, from, :busy)`: **(Mapeamento de `receive getforks()` com garfo ocupado)** Se o recurso já estiver em uso, o retorno `{:noreply, {:busy_waiting, from}}` instrui o servidor a **reter a resposta**. Sem uma resposta, o processo do filósofo solicitante fica automaticamente bloqueado e suspenso pela arquitetura da BEAM. Guardamos a tupla de identificação do cliente (`from`) no estado interno.
* `def handle_cast(:rel_forks, :busy)`: Acionado quando um filósofo libera o garfo e não há fila de espera. O estado retorna para `:available`.
* `def handle_cast(:rel_forks, {:busy_waiting, pending_philosopher})`: **(Mapeamento de `receive relforks()` acordando o próximo da fila)** Quando o filósofo atual libera o garfo, mas há outro na fila, o garçom intercepta a identidade `pending_philosopher` armazenada, dispara um sinal de desbloqueio manual via `GenServer.reply/2`, e mantém seu estado como `:busy` para o novo detentor.

---

### 2. Módulo `Philosopher` (O Filósofo / Processo Ativo)

Este módulo mapeia o bloco comportamental concorrente `process Philosopher[i = 0 to 4]`.

* `spawn_link(fn -> p_loop(id) end)`: Cria um processo leve e isolado para o filósofo, atrelando seu ciclo de vida ao processo pai para fins de monitoramento e resiliência.
* `{first, second} = if id == 4, do: {0, 4}, else: {id, id + 1}`: **(Mapeamento do bloco de assimetria `if (i == 4)`)** Aplica a quebra estratégica de simetria circular para mitigar a ocorrência de *deadlocks*. O último filósofo requisita os garçons na ordem inversa.
* `Waiter.get_forks(first)` / `Waiter.get_forks(second)`: Chamadas bloqueantes e sequenciais do filósofo para adquirir os dois recursos antes de progredir para a região crítica.
* `Waiter.rel_forks(first)` / `Waiter.rel_forks(second)`: Devolução não bloqueante dos recursos utilizados.
* `p_loop(id)`: **(Mapeamento estrutural do `while(true)`)** Em Elixir, loops infinitos usam recursão. Por ser uma chamada no último ponto de execução da função (*Tail Call Optimization*), a máquina virtual reutiliza o mesmo frame de pilha na memória, evitando estouros (*Stack Overflow*) e criando um laço contínuo de consumo fixo de memória.

---

## 🚀 Como Executar o Projeto

### Pré-requisitos
* Ter o [Elixir](https://elixir-lang.org/install.html) instalado na sua máquina (versão 1.12 ou superior recomendada).

### Execução como Script
1. Salve o código em um arquivo chamado `jantar.exs`.
2. Abra o terminal na pasta do arquivo e execute:
   ```bash
   elixir jantar.exs
