# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Todos.Repo.insert!(%Todos.SomeModel{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
defmodule DatabaseSeeder do
  def add_random_todo do
    Todos.Repo.insert!(%Todos.Todo{name: Faker.Company.En.bullshit})
  end
end

Enum.each(1..1000, fn(n) -> DatabaseSeeder.add_random_todo end)
