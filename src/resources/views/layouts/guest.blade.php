<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ isset($title) ? $title.' · ' : '' }}CRM AreaCli</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="min-h-screen bg-slate-50">
    @if (\App\Demo\DemoMode::enabled())
        <div class="bg-amber-100 px-4 py-2 text-center text-sm text-amber-900" role="note">
            Demonstração: os dados são fictícios e recriados todo dia às {{ config('crm.demo.reset_at') }}, horário de Brasília. Os arquivos que você enviar são descartados sem ser lidos.
        </div>
    @endif
    <main class="mx-auto flex min-h-[80vh] max-w-md flex-col justify-center gap-6 p-6">
        <p class="text-center text-3xl font-bold text-slate-900">CRM</p>
        {{ $slot }}
    </main>
</body>
</html>
