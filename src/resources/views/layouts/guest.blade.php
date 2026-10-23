<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <link rel="icon" type="image/svg+xml" href="/brand/simbolo.svg">
    <title>{{ isset($title) ? $title.' · ' : '' }}CRM AreaCli</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="min-h-screen bg-surface">
    @if (\App\Demo\DemoMode::enabled())
        <div class="bg-brand-yellow px-4 py-2 text-center text-sm text-brand-navy" role="note">
            Demonstração: os dados são fictícios e recriados todo dia às {{ config('crm.demo.reset_at') }}, horário de Brasília. Os arquivos que você enviar são descartados sem ser lidos.
        </div>
    @endif
    <main class="mx-auto flex min-h-[80vh] max-w-md flex-col justify-center gap-6 p-6">
        <img src="/brand/logotipo-negativo.svg" alt="AreaCli" class="mx-auto h-16 w-auto rounded-lg">
        {{ $slot }}
    </main>
</body>
</html>
