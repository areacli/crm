<?php

namespace App\Notifications;

use Illuminate\Notifications\Notification;

/** Aviso dentro do sistema: o usuário foi ligado a um credor (A5, R36a). */
final class LinkedToTenant extends Notification
{
    public function __construct(
        private readonly string $tenantName,
        private readonly string $actorName,
        private readonly string $profileName,
    ) {}

    /** @return list<string> */
    public function via(object $notifiable): array
    {
        return ['database'];
    }

    /** @return array<string, mixed> */
    public function toDatabase(object $notifiable): array
    {
        return ['title' => "{$this->actorName} ligou você a {$this->tenantName}", 'body' => "Perfil: {$this->profileName}."];
    }
}
