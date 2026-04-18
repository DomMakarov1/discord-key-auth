-- CreateTable
CREATE TABLE "HwidLoginState" (
    "id" SERIAL NOT NULL,
    "hwid" TEXT NOT NULL,
    "failCount" INTEGER NOT NULL DEFAULT 0,
    "escalation" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMP(3),
    "dayKey" TEXT NOT NULL DEFAULT '',
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HwidLoginState_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AccessBan" (
    "id" SERIAL NOT NULL,
    "hwid" TEXT,
    "ip" TEXT,
    "reason" TEXT,
    "createdByDiscordId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AccessBan_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "HwidLoginState_hwid_key" ON "HwidLoginState"("hwid");

-- CreateIndex
CREATE INDEX "AccessBan_hwid_idx" ON "AccessBan"("hwid");

-- CreateIndex
CREATE INDEX "AccessBan_ip_idx" ON "AccessBan"("ip");
