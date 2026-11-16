# Publica o projeto no GitHub. Rode no PowerShell, DENTRO da pasta do projeto (onde está este arquivo):
#     powershell -ExecutionPolicy Bypass -File .\publicar-github.ps1
# Antes: crie o repositório VAZIO no GitHub (sem README) e deixe a URL à mão, por exemplo
#     https://github.com/SEU_USUARIO/passa-rapido.git
# O script: confere o Git, confirma seu nome e e-mail dos commits, coloca o link do repositório no README.txt e
# no ENTREGA-links.txt, faz o commit e envia (push). Se o Git pedir login, entre pela janela do navegador.

$ErrorActionPreference = 'Stop'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host 'Git não encontrado. Instale em https://git-scm.com/download/win e rode de novo.' -ForegroundColor Red; exit 1
}
if (-not (Test-Path 'README.txt') -or -not (Test-Path 'app') -or -not (Test-Path 'database')) {
  Write-Host 'Rode este script dentro da pasta do projeto (onde ficam README.txt, app e database).' -ForegroundColor Red; exit 1
}
if (-not (Test-Path '.git')) { git init -b main | Out-Null }

$nome = git config user.name
$email = git config user.email
Write-Host "Identidade atual do Git: $nome <$email>"
$troca = Read-Host 'Usar outra identidade nos commits? (s/N)'
if ($troca -match '^[sS]') {
  $nome = Read-Host 'Nome'; $email = Read-Host 'E-mail (aparece no GitHub)'
  git config user.name $nome; git config user.email $email
}

$url = Read-Host 'URL do repositório no GitHub (termina em .git)'
if ($url -notmatch '^https://github\.com/.+/.+') { Write-Host 'URL inválida.' -ForegroundColor Red; exit 1 }
$link = $url -replace '\.git$',''

foreach ($arq in 'README.txt','ENTREGA-links.txt') {
  $t = [System.IO.File]::ReadAllText((Resolve-Path $arq))
  $t = $t.Replace('[preencher: link do GitHub]', $link).Replace('[colar aqui o link do repositório]', $link)
  [System.IO.File]::WriteAllText((Resolve-Path $arq), $t, (New-Object System.Text.UTF8Encoding($false)))
}

git add .
git status --short | Select-Object -First 15
git commit -m 'Passa Rápido: versão final da Global Solution 2' | Out-Host
git branch -M main
if (git remote) { git remote set-url origin $url } else { git remote add origin $url }
git push -u origin main
Write-Host ''
Write-Host "Pronto: $link" -ForegroundColor Green
Write-Host 'Agora: Settings > Collaborators > adicionar o tutor, e conferir o repositório em janela anônima (se for privado, deve pedir login).'
