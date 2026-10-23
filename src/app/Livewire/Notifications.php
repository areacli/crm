<?php

namespace App\Livewire;

use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/** Sino do topo: avisos dentro do sistema do usuário (por exemplo, "ligado a um credor"), com marcar como lido. */
final class Notifications extends Component
{
    public function markAllRead(): void
    {
        Auth::user()->unreadNotifications->markAsRead();
    }

    public function render()
    {
        $user = Auth::user();

        return view('livewire.notifications', [
            'unread' => $user->unreadNotifications()->latest()->limit(10)->get(),
            'count' => $user->unreadNotifications()->count(),
        ]);
    }
}
