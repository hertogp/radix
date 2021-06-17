defmodule Radix.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/hertogp/radix"

  def project do
    [
      app: :radix,
      version: @version,
      elixir: "~> 1.11",
      name: "Radix",
      description: "A bitwise radix tree that stores any value under a bitstring key",
      deps: deps(),
      docs: docs(),
      package: package(),
      aliases: aliases()
    ]
  end

  defp aliases() do
    [docz: ["docs", &cp_images/1]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  defp package do
    %{
      licenses: ["MIT"],
      maintainers: ["hertogp"],
      links: %{"GitHub" => @url}
    }
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end

  defp docs do
    [
      main: Radix,
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @url
    ]
  end

  defp cp_images(_) do
    # the repo does not track `/doc/` or any subdirectories.  Github
    # links work if documenitation links to images like `![xx](img/a.png)`
    #
    # While on hex.pm, image links are taken to be relative to the repo's
    # root/doc directory (which is untracked btw).  Hence, the img/*.dot
    # file are processed into img/*.png files, after which the img/*.png
    # files are copied to doc/img/*.png so everybode is happy!

    # ensure the (untracked) doc/img directory for hex.pm
    Path.join("doc", "img")
    |> File.mkdir_p!()

    # process all img/*.dot files into img/*.dot.png image files
    Path.wildcard("img/*.dot")
    |> Enum.map(fn file -> System.cmd("dot", ["-O", "-Tpng", file]) end)

    # copy img/*.png to doc/img/*.png
    Path.wildcard("img/*.png")
    |> Enum.map(fn src -> {src, Path.join("doc", src)} end)
    |> Enum.map(fn {src, dst} -> File.cp!(src, dst) end)
  end
end
