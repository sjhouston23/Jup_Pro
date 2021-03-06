program HydrogenPrecip
!*******************************************************************************
!* Created by Stephen J. Houston 06.22.20
!*******************************************************************************
!* This program simulates the path of an energetic hydrogen ion as it penetrates
!* into the Jovian atmosphere. Different initial energies are considered.
!* I use 1-25,000 keV as initial energies for this exploratory work.
!* A random pitch angle is considered for the precipitating ion following a
!* cosine distribution.
!* A Monte Carlo simulation is used to determine the type of collision
!* and where the collision occurs. To calculate the collision path dN
!* I use 1-Prob = exp{-sigtot*dN}. After each collision I track the secondary
!* electrons produced, as well as the new ion energy. The results are binned by
!* column density which correspond to a particular altitude.
!******************************
!* External files required:
!* The secondary electron distributions are calculated by other codes based on
!* cross sections calculated by Dave Schultz.
!* The singly-differential cross sections for the ion+H2 processes are read in
!* at the beginning of the model. These are as function of energy.
!* The distribution functions for ejected electrons are read as eprobfunc and
!* aprobfunc. These are as function of energy and angle, respectively.
!* Ejected electron energy is calculated in this model by using the cross
!* sections and energy loss model presented in Schultz et al., 2018.
!* See input files for the files that are needed.
!******************************
!* Goals:
!* 1. Read in the distribution functions for all available collision types,
!* charge states and energies and store this info in matrices
!* 2. Set a matrix with the angular distribution to determine wether the
!* electron will be scattered forward or backward in a collision. The incident
!* ion pitch angle is added to the ejected electron angle.
!* 3. Read in all the total xs calculated by Dave.
!* 4. Create altitude bins and find the corresponding column density.
!* 5. Set the initial conditions for the ion -> charge state and initial energy,
!* incident angle (normally kept at 0) and initial pitch angle
!* 6. Follow ion as it penetrates the atmosphere and has collisions determined
!* by the MC.
!* 7. Track the charge state of the ion, number and energy of electrons
!* produced, and ion energy at each altitude bin in the atmosphere, until the
!* ion runs out of energy (E<1 keV/u)
!*******************************************************************************

use,intrinsic :: ISO_FORTRAN_ENV !Used for int64 integers
use formatting !Formatting module to avoid cluttering the end of the program
implicit none

!**************************** Variable Declaration *****************************
!* Do-loop variables:
integer i,j,k,l,run,ion,intdum

!* Computational time variables:
integer t1,t2,clock_maxTotal,clock_rateTotal !Used to calculate comp. time
integer t3,t4,clock_max,clock_rate !Used to calculate comp. time
integer hrs,min
real sec

!* Atmosphere variables:
integer atmosLen !"Length" of the atmosphere (3000 - -88 km) with 2 km steps]
real*8 dN,dNTot,dZ,dZTot !Change in atmosphere
parameter(atmosLen=1544) !Length of the atmosphere
real*8,dimension(atmosLen) :: totalCD,altitude,altDelta,totalDens,H
!* Total column density, array of altitude in km, alt bin size, scale height
real*8 dum

!* Hydrogen ion variables:
! PROCESSES (Proc)
integer Proc,nProc !Number of processes
integer SI,DI,TI,SS,DS,SC,DC,TEX,PEX,ES! Processes
parameter(nProc=10)
parameter(SI=1,DI=2,TI=3,SS=4,DS=5,SC=6,DC=7,TEX=8,PEX=9,ES=10)
! *****
! SI  = 1  - Single Ionization
! DI  = 2  - Double Ionization
! TI  = 3  - Transfer Ionization
! SS  = 4  - Single Stripping
! DS  = 5  - Double Stripping
! SC  = 6  - Single Capture
! DC  = 7  - Double Capture
! TEX = 8  - Target Excitation
! PEX = 9  - Projectile Excitation
! ES  = 10 - Elastic Scattering
! *****

!CHARGE STATES (ChS)
integer ChS,ChS_init,ChS_old,nChS !Number of hydrogen charge states: -1, 0, +1
parameter(nChS=3)
!ENERGY
integer Eng,energy,nEnergiesNorm,nEnergiesJuno !Number of inital ion energies
integer nEnergies,EnergySwitch !Used to decide which set of energy bins
integer nInterpEnergies !Number of interpolated ion energies
real*8 E,dE
parameter(nEnergiesNorm=15,nEnergiesJuno=37,nInterpEnergies=25000)
real*8,dimension(nEnergiesNorm) :: IonEnergyNorm !Initial ion energies normally
real*8,dimension(nEnergiesJuno) :: IonEnergyJuno !Initial ion energies for Juno
real*8,allocatable,dimension(:) :: IonEnergy !Initial ion energies once decided
!CHARGE STATE DISTRIBUTION
integer nHydEngBins !Number of energy bins for charge state fractions
real*8 HydEngBinSize !Size of energy bins for charge state fractions
parameter(nHydEngBins=25000,HydEngBinSize=1.0)
integer(kind=int64) :: HydVsEng(nChS,nHydEngBins) !Charge state fractions
real*8 engBins(nHydEngBins),HydEngBins(nHydEngBins) !Hydrogen energy bins
!STOPPING POWER (SP)
integer nSPBins !Number of stopping power bins vs. energy
real*8 SPBinSize !Size of bins
parameter(nSPBins=25000,SPBinSize=1.0)
real*8 dEsp,xsTotSP,dEold
integer(kind=int64),dimension(nSPBins) :: nSPions
real*8,dimension(nSPBins) :: SPBins,SPvsEng,xsTotvsEng,dEvsEng,dNvsEng
real*8,dimension(nProc,nSPBins) :: dEvsEngPID,ionsPID
!MASS
real*8 mass !Atomic mass of hydrogen (1.00784)
parameter(mass=1.00784)
!OTHER VARIABLES
integer trial,excite,elect,disso,PID,nIons
integer numSim,dpt,maxDpt
character(len=100) arg !For reading in trial number on the cluster

integer(kind=int64),dimension(nProc) :: collisions !Counter
real*8,dimension(nProc) :: dEcollisions !Counter
integer(kind=int64),dimension(nProc,nChS,atmosLen) :: hydrogen
real*8 incB,kappa,pangle
real*8,dimension(nChS,nInterpEnergies) :: xs_Total !SigTot for dN calculation
real*8,dimension(nProc,nChS,nInterpEnergies) :: xs !All xs

!* Ejected electron variables:
integer neProc !Number of processes that eject electrons
integer nE2strBins !Number of 2 stream bins
integer eSI,eDI,eTI,eSS,eDS !Electron ejection processes

parameter(neProc=5) !Number of processes that eject electrons
parameter(nE2strBins=260) !Number of 2 stream bins
parameter(eSI=1,eDI=2,eTI=3,eSS=4,eDS=5) !Electron ejection processes

integer eProc !Electron process number
integer nElect !Number of electron counter
integer eBin !Electron energy bin in 2-stream format
integer DSelect !Double stripping electron tracker for transform
real*8 eEnergyTmp,eAngleTmp,eEnergy,eAngle
real*8 eAngleSS,eEnergySS,eAngleDS(2),eEnergyDS(2) !SS/DS elec transforms
integer(kind=int64) :: totalElect !Total Electrons
integer(kind=int64),dimension(atmosLen,nE2strBins) :: electFwd,electBwd

!* Output production variables:
integer(kind=int64),dimension(atmosLen) :: Hp,H2p !H+ and H2+ counts
integer(kind=int64) :: H2Ex(atmosLen) !Excited H2 counter
real*8 norm !Normalization variable to per ion per cm
real dissRan !Random number to determine dissociation probability

!* Random Number Generator:
integer k1,k2,lux,in
parameter(k1=0,k2=0,lux=3) !lux set to 3 for optimal randomness and timeliness
real ranVecA(1002)
real,allocatable :: angle(:)

!* Output Variables:
integer nOutputFiles !Number of output files
parameter(nOutputFiles=10)
character(len=100) filename,files(nOutputFiles) !Output file names
!****************************** Data Declaration *******************************
!* Initial ion enegy input:
data IonEnergyNorm/1.0,2.0,5.0,10.0,25.0,50.0,75.0,100.0,200.0,500.0,1000.0,&
     2000.0,5000.0,10000.0,25000.0/
! data IonEnergy/10.625,15.017,20.225,29.783,46.653,59.770,77.522,120.647,&
!                218.125,456.250/ !Juno energy bins from JEDI
!* Initial ion enegy input from interpoalted JEDI bins:
data IonEnergyJuno/10.625,11.619,12.656,13.786,15.017,16.177,17.427,18.774,&
     20.225,22.280,24.543,27.036,29.783,33.319,37.276,41.702,46.653,49.634,&
     52.806,56.180,59.770,63.785,68.070,72.642,77.522,86.586,96.710,108.018,&
     120.647,139.90,162.223,188.108,218.125,262.319,315.467,379.384,456.250/
data engBins/nHydEngBins*HydEngBinSize/ !Used for sulfur binning
data files/'ChargeStateDistribution','H+_Prod','H2+_Prod','H2*_Prod',&
     'Collisions','Photons_CX','Photons_DE','Stopping_Power','2Str_Elect_Fwd',&
     '2Str_Elect_Bwd'/
!********************************** Run Time ***********************************
!Calculate the total computational run time of the model:
call system_clock (t1,clock_rateTotal,clock_maxTotal)
!**************************** Initialize Variables *****************************
altitude=0.0;totalCD=0.0;totalDens=0.0;H=0.0;altDelta=0.0;xs=0.0
xs_Total=0.0;HydEngBins=0.0;SPBins=0.0;dEvsEngPID=0.0
!**************************** Create the Atmosphere ****************************
open(unit=200,file='./Atmosphere/Input/JunoColumnDensity_2km.dat',status='old')
open(unit=201,file='./Atmosphere/Input/JunoAtmosphere_2km.dat',status='old')
read(200,*);read(201,*) !Skip header lines
do i=1,atmosLen
  read(200,*)altitude(i),dum,dum,dum,dum,totalCD(i)!Read in the atmosphere
  read(201,*)dum,dum,dum,dum,dum,totalDens(atmosLen-i+1),dum,dum,H(atmosLen-i+1)
  altDelta(i)=2.0
end do
close(200) !Close column density file
close(201) !Close atmosphere file
!*************************** Get SIM cross-sections ****************************
open(unit=203,file='./XS/Integral_XS_Normalized_Interpolated.dat',status='old')
do Proc=1,nProc
  do i=1,4
    read(203,*)
  end do
  do Eng=1,nInterpEnergies
    read(203,20300) intdum,(xs(Proc,ChS,Eng),ChS=1,nChS)
  end do
end do
open(unit=204,file='./XS/Integral_XS_Normalized_Sum_Interpolated.dat',&
     status='old')
read(204,*)
do Eng=1,nInterpEnergies
  read(204,20300) intdum,(xs_Total(ChS,Eng),ChS=1,nChS)
end do
close(203)
close(204)
20300 format(I6,2x,3(1x,ES11.5e2))
! 20400 format(I6,2x,3(1x,ES11.5e2))
!**************************** Various Bin Creation *****************************
! !2-Stream energy bins:
! do i=1,nE2strBins
!   es=es+del(i)
!   E2str(i)=Es
! end do
!Hydrogen bins for charge state fractions:
HydEngBins(1)=HydEngBinSize
do i=2,nHydEngBins
  HydEngBins(i)=HydEngBins(i-1)+engBins(i) !1-2000 keV/u
end do
!Stopping power bins:
SPBins(1)=1.0
do i=2,nSPBins
  SPBins(i)=SPBins(i-1)+SPBinSize
end do
! !Bins for ejected electron energy:
! es=0.0
! do i=1,790
!   es=es+delAVGe(i)
!   elecEbins(i)=es
! end do
! !Bins for ejected electron angle:
! do i=1,180
!   elecAbins(i)=i
! end do
!**************************** Energy Bins Selection ****************************
!* The following run number corresponds to the energy in keV/u
!* Juno:
!* 1=10.625, 2=11.619, 3=12.656, 4=13.786, 5=15.017, 6=16.177, 7=17.427,
!* 8=18.774, 9=20.225, 10=22.280, 11=24.543, 12=27.036, 13=29.783, 14=33.319
!* 15=37.276, 16=41.702, 17=46.653, 18=49.634, 19=52.806, 20=56.180, 21=59.770,
!* 22=63.785, 23=68.070, 24=72.642, 25=77.522, 26=86.586, 27=96.710, 28=108.018,
!* 29=120.647, 30=139.90, 31=162.223, 32=188.108, 33=218.125, 34=262.319,
!* 35=315.467, 36=379.384, 37=456.250
!* Normal:
!* 1=1, 2=10, 3=50, 4=75, 5=100, 6=200, 7=500, 8=1000, 9=2000
!*******************************************************************************
EnergySwitch=1 !1 for normal energy bins, 2 for Juno energy bins
if(EnergySwitch.eq.1)then !Normal energy bins
  nEnergies=nEnergiesNorm
  allocate(IonEnergy(nEnergies))
  IonEnergy=IonEnergyNorm
elseif(EnergySwitch.eq.2)then !JEDI interpolated energy bins
  nEnergies=nEnergiesJuno
  allocate(IonEnergy(nEnergies))
  IonEnergy=IonEnergyJuno
end if
! write(*,'(37(F7.3,","))') (IonEnergyJuno(i)/2.0,i=1,37)
!*******************************************************************************
!******************************** MAIN PROGRAM *********************************
!*******************************************************************************
nIons=250 !Number of ions that are precipitating
! trial=12 !The seed for the RNG
call get_command_argument(1,arg)
read(arg,'(I100)') trial !The seed for the RNG
do run=15,15!1,nEnergies !Loop through different initial ion energies
  call system_clock(t3,clock_rate,clock_max) !Comp. time of each run
  energy=int(IonEnergy(run))
  write(*,*) "Number of ions:         ",nIons
  write(*,*) "Initial energy:         ",energy,'keV/u'
  write(*,*) "Trial number (RNG Seed):",trial
  write(*,F3) !'**'
!*************************** Random Number Generator ***************************
  !k1=0,k2=0 Should be set to zero unless restarting at a break (See ranlux.f08)
  in=trial !RNG seed
  call rluxgo(lux,in,k1,k2) !Seed the RNG
  allocate(angle(nIons)) !Want the same number of angles as ions
  call ranlux(angle,nIons) !Calculate all the angles to be used
!********************* Reset Counters For New Ion Energies *********************
  Hp =0;totalElect=0;dEcollisions=0.0
  H2p=0;hydrogen    =0;electFwd  =0;electBwd  =0;maxDpt   =0
  H2Ex  =0;collisions=0;HydVsEng  =0
  SPvsEng=0.0;xsTotvsEng=0.0;dEvsEng=0.0;dNvsEng=0.0;nSPions=0
!************************ Ion Precipitation Begins Here ************************
  write(*,*) 'Starting Ion Precipitation: ', energy,'keV/u' !Double check energy
  do ion=1,nIons !Each ion starts here
    !*****************************
    !Initial Conditions:
    pangle=0.0         !Reset the pitch angle for every run
    incB  =0.0         !Incident B-field
    kappa =0.0         !Used to account for pitch angle
    numSim=energy*1000 !Number of simulations for a single ion. Must be great !~
                       !enough to allow the ion to lose all energy
    E=energy           !Start with initial ion energy
    ChS_init=3         !1 is an initial charge state of -1, 3 is +1
    ChS=ChS_init       !Set the charge state variable that will be changed
    ChS_old=ChS_init   !Need another charge state variable for energyLoss.f08
    dNTot=0.0          !Reset the column density to the top of the atm.
    dZTot=3000.0       !Start from the top of the atmosphere
    dpt=4              !Depth of penetration for bins. (integer value)
    !Beginning scale height (H) at 4 or 5 seems to be more accurate than 1-3
    l=0                !Used as index for dN calculation (ranVecA(l))
    excite=0           !CollisionSim output
    PID=0              !Process identification numbers
    !*****************************
    pangle=(2.0*atan(1.0))-acos(0.0) !Pitch angle calculation has a
    ! pangle=(2.0*atan(1.0))-acos(angle(ion)) !Pitch angle calculation has a
    !cosine dist. Straight down is pitch angle of 0, random number must be 0
    write(*,*) 'Ion Number: ',ion,' Pitch angle: ',pangle*90/acos(0.0)
    kappa=1.0/(cos(pangle)*cos(incB)) !Used to convert from ds to dz
    call ranlux(ranVecA,1002) !Get a random vector for collisions
    do i=1,numSim !This loop repeats after each collision until E < 1 keV/u
      !*****************************
      !Reset Variables:
      dN=0.0;dZ=0.0;dE=0.0 !Change in column density, altitude, energy
      dEsp=0.0;xsTotSP=0.0;dEold=0.0 !Stopping power variables
      !*****************************
      call CollisionSim(nint(E),xs,xs_Total,ChS,excite,elect,disso,PID)
      collisions(PID)=collisions(PID)+1 !Count collisions
1000 continue
      l=l+1
      if(l.ge.1000)then
        !Filling ranVecA with a huge amount of numbers is a big time waster
        call ranlux(ranVecA,1002) !Only get ranVecA as needed
        l=1 !Reset l back to 1 (Start at 1 because ranVecA(l) is called next)
      end if
      !Calculate how far ion moves before a collision (dN)
      dN=-log(1-ranVecA(l))/xs_Total(ChS_old,nint(E))
      !Sometimes ranVecA is small enough to make DN 0
      if(dN.lt.1.0)goto 1000 !Get a new dN
      xsTotSP=xs_Total(ChS_old,nint(E)) !Used for stopping power calc.
      dNTot=dNTot+dN !Total change in column density
      do j=1,atmosLen !Loop through all of the atmosphere
        if(dNTot.le.totalCD(j+1))then !Move to proper CD of atmosphere
          !Calculate change in z based on the movement through the column dens.
          dZ=log((cos(pangle)*dN/(totalDens(dpt)*H(dpt)))+1)*H(dpt)
          dZTot=dZTot-dZ*1e-5 !Convert to km and keep subtracting from alt.
          do k=1,atmosLen !Loop through the atmosphere again
            if(dZTot.gt.altitude(k))then
              dNTot=totalCD(k) !So ion doesn't get stuck in a bin
              dpt=k !dpt is now the bin corresponding to depth
              if(dpt.gt.maxDpt) maxDpt=dpt !Used to see how deep we go
              goto 2000 !Get out of the do-loop that finds depth of penetration
            end if !Altitude if-statemet
          end do !Altitude do-loop
          !If we get here, then the ion has went through the entire atmosphere
          write(*,*)"JupSulPrecip.f08: WARNING: Ion exited the bottom of the &
                    &atmosphere, proceeding to next ion."
          goto 5000 !Continue on to the next ion
        end if !Column density if-statement
      end do !Column density do-loop
2000 continue
!*********************** Secondary Electron Calculations ***********************
      !*****************************
      !Reset Variables:
      eEnergy =0.0;eEnergyTmp=0.0 !Ejected electron energy (eV)
      eAngle  =0.0;eAngleTmp =0.0 !Ejected electron angle (°)
      eAngleSS=0.0;eEnergySS =0.0 !Single stripping transform variables (eV)
      eAngleDS=0.0;eEnergyDS =0.0 !Double stripping transform variables (°)
      nElect  =0  ;eProc     =0   !Ejected electron integers
      DSelect =1                  !Double stripping electron counter
      !*****************************
      if(PID.eq.SC.or.PID.eq.DC.or.PID.eq.TEX.or.PID.eq.PEX.or.PID.eq.ES)then
        nElect=12 !No electrons
      end if
      do j=1,elect !Loop through all of the ejected electrons
        if(PID.eq.SI.and.nElect.le.10)then !Single Ionization
          eProc=eSI !1
          nElect=nElect+10 !After one time, don't want to come back in here
        elseif(PID.eq.DI.and.nElect.le.10)then !Double Ionization
          eProc=eDI !2
          nElect=nElect+5 !After two times, don't want to come back in here
        elseif(PID.eq.TI.and.nElect.le.10)then !Transfer Ionization
          eProc=eTI !3
          nElect=nElect+10 !After one time, don't want to come back in here
        elseif(PID.eq.SS.and.nElect.ge.11)then !Single Stripping
          eProc=eSS !4
        elseif(PID.eq.DS.and.nElect.ge.11)then !Double Stripping
          eProc=eDS !5
        end if
        call EjectedElectron(E,eProc,ChS_old,eEnergyTmp,eAngleTmp,eBin)
        nElect=nElect+1
        if(eProc.eq.eSS)then
          eEnergySS=eEnergyTmp !Units of eV
          eAngleSS=eAngleTmp !Need the ejection angle for energy transformation
        end if
        if(eProc.eq.eDS)then
          eEnergyDS(DSelect)=eEnergyTmp !Units of eV
          eAngleDS(DSelect)=eAngleTmp
          DSelect=DSelect+1 !Double stripping electron
        end if
        totalElect=totalElect+1 !Total number of electrons produced
        eAngle=eAngleTmp+(pangle*90/acos(0.0))
        !Must add the pitch angle to ejected elect angle. pangle = [0,acos(0.0)]
        if(eAngle.le.90.0)then !Counting electrons going forward (downward)
          electFwd(dpt,eBin)=electFwd(dpt,eBin)+1 !Elect fwd vs. alt. and eng.
        elseif(eAngle.le.270.0)then !Electrons going backward (0 is down)
          electBwd(dpt,eBin)=electBwd(dpt,eBin)+1 !Elect bwd vs. alt. and eng.
        else !If the electron is ejected so far backward it's going fwd again
          write(*,*) "JupSulPrecip.f08: WARNING: Elect ejection angle &
                     &greater than 270 degrees."
        end if
        !Only want to add the electron energies for the some processes since SS
        !and DS have to be transformed into a different reference frame
        if(eProc.le.3)eEnergy=eEnergy+eEnergyTmp !Units of eV
      end do !End of electron ejection do loop (j=1,elect)
!************************* Counting Photon Production **************************
!* Note:
!*  A photon count at a specific altitude and charge state means that there was
!*  a photon producing collision at that specific altitude and the resultant ion
!*  was at the recorded charge state. That means, a collision that goes from
!*  H^+ to H will be recorded as H; therefore, the H^+ bin will never
!*  produce a photon. The last bin should ALWAYS be 0. Each processes can only
!*  create one photon, if it's a photon producing collision.
!*  Direct excitation (photonsDE) producing collisions:
!*    PEX(9)
!*  Charge exchange (photonsCX) producing collisions:
!*    TI(3), SC(6), DC(7)
!*  This is all done in the writing of the output files. Photon productions are
!*  files 118 and 119 using the hydrogen variable.
!*******************************************************************************
!********************* Counting Hydrogen & H/H2 Production *********************
      !Hydrogen variable is the precipitating ions
      hydrogen(PID,ChS,dpt)=hydrogen(PID,ChS,dpt)+1 !Hydrogen prod
      !Hydrogen variable is what shows photon production, depending on processes
      !Hp, H2p, and H2Ex is all atmospheric hydrogen, not precipitating
      if(disso.eq.2)then
        Hp(dpt)=Hp(dpt)+2 !Number of H^+ produced
      elseif(disso.eq.1)then
        call ranlux(dissRan,1) !Random number to determine dissociation
        if(dissRan.le.0.1)then !10% chance of dissociation (H + H^+)
          Hp(dpt)=Hp(dpt)+1
        else !90% chance of no dissociation
          H2p(dpt)=H2p(dpt)+1
        end if
      elseif(disso.eq.0.and.PID.eq.TEX)then !TEX never dissociates,result is H2*
        H2Ex(dpt)=H2Ex(dpt)+1
      end if
!************************** Energy Loss Calculations ***************************
      call energyloss(E,ChS_old,eEnergy,PID,eEnergySS,eAngleSS,&
                     &eEnergyDS,eAngleDS,dE)
      dEsp=(dE)/dN !stopping power (calc before dE is recalculated)
      dEold=dE
      dE=(1/mass)*(1.0e-3)*dE*kappa !Total dE function
      if(dN.lt.0.0)then !Change in column density should never be less than 0
        ! write(206,10001) E,dEsp,dE,dN,dEold,PID,ChS_old
        write(*,10001) E,dEsp,dE,dN,dEold,PID,ChS_old,ChS
      end if
      ! if(numSim.eq.10) stop
      dEcollisions(PID)=dEcollisions(PID)+dE
!********************* Hydrogen Charge State Distribution **********************
      do j=1,nHydEngBins
        if(E.le.HydEngBins(j))then
          HydVsEng(ChS,j)=HydVsEng(ChS,j)+1
          goto 3000
        end if
      end do
3000 continue
      do j=1,nSPBins
        if(E.le.SPBins(j))then
          SPvsEng(j)=SPvsEng(j)+dEsp !Stopping power vs energy
          xsTotvsEng(j)=xsTotvsEng(j)+xsTotSP !Total cross-section vs energy
          dEvsEng(j)=dEvsEng(j)+dEold !Change in energy vs energy
          dEvsEngPID(PID,j)=dEvsEngPID(PID,j)+dEold
          ionsPID(PID,j)=ionsPID(PID,j)+1
          dNvsEng(j)=dNvsEng(j)+dN !Change in column density vs energy
          nSPions(j)=nSPions(j)+1 !Number of ions in each energy bin
          goto 4000
        end if
      end do
4000 continue
      E=E-dE
      ! ChS=ChS_init
      ChS_old=ChS !Assign newly acquired charge state to old variable
      if(E.lt.1.0) goto 5000 !Stop once the energy is less than 1 keV/u
      if(i.eq.numSim)then
        write(*,*) 'JupSulPrecip.f08: ERROR: numSim not large enough.'
        write(*,*) 'JupSulPrecip.f08: Ion energy was: ',E
        goto 5000
      end if
    end do !End of i=1,numSim loop (E < 1 keV/u)
5000 continue
  end do !End of ion=1,nIons loop
  ! energy=210
!******************************** Output Header ********************************
  write(*,*) '--------------------------NEW RUN---------------------------'
  write(*,*) 'Number of ions: ', nIons
  write(*,*) 'Initial energy: ', energy, 'keV'
  write(*,*) 'Trial number:   ', trial
  write(*,F3) !'**'
  !******* Check various electron counters
  write(*,*) 'Sum of total electrons foward:         ',sum(electFwd)
  write(*,*) 'Sum of total electrons backward:       ',sum(electBwd)
  write(*,*) 'Sum of total electrons foward+backward:',sum(electFwd+electBwd)
  write(*,*) 'Sum of total electrons:                ',totalElect
  write(*,F1)'Max Depth:',altitude(maxDpt)
!********** Open output data files for each set of initial energies ************
  do i=1,nOutputFiles
    write(filename,"('./Output/',I0,'/',A,'-',I0,'.dat')")&
      energy,trim(files(i)),trial
    open(unit=100+i,file=trim(filename))
  end do
!***************************** Write out to files ******************************
  norm=nIons*2e5 !Normalization condition to per ion per cm
!*** Charge state distribution
  write(101,H01) !Hydrogen charge state distribution header
  do i=2,nHydEngBins !Hydrogen charge state distribution
    write(101,F01) HydEngBins(i)-(HydEngBinSize/2.0),&
      (real(HydVsEng(j,i))/real(sum(HydVsEng(:,i))),j=1,nChS)
  end do
!*** H production
  write(102,H02) !H^+ Header
  write(103,H03) !H_2^+ Header
  write(104,H04) !H_2^* Header
  do i=1,atmosLen !Loop through the atmosphere
    write(102,F02) altitude(i),Hp(i)/norm !H^+ production
    write(103,F02) altitude(i),H2p(i)/norm !H_2^+ production
    write(104,F02) altitude(i),H2Ex(i)/norm !H_2^* production
  end do
!*** Collision counters
  write(105,F03) (Coll(i),i=1,nProc) !Collisions header
  write(105,F04) (collisions(i),i=1,nProc),sum(collisions)
  write(105,F4) !'--'
  write(105,F05) (real(collisions(i))/real(sum(collisions))*100,i=1,nProc)
!*** Photon production
  write(106,N01) !CX note
  write(107,N02) !DE note
  do i=1,2 !Loop through CX and DE headers
    write(105+i,*) !Blank space
    write(105+i,H09) !Initial input header
    write(105+i,*) !Blank space
    write(105+i,H05) !Altitude integrated photon production header
    write(105+i,H06) !Charge state header
  end do
!*** Altitude integrated photon production
  write(106,F06) altDelta(1),& !CX - TI, SC, DC
    (real(sum(hydrogen(TI,ChS,:))+sum(hydrogen(SC,ChS,:))+&
    sum(hydrogen(DC,ChS,:)))/norm,ChS=1,nChS)
  write(107,F06) altDelta(1),& !DE - PEX
    (real(sum(hydrogen(PEX,ChS,:)))/norm,ChS=1,nChS)
  do i=1,2 !Loop through CX and DE headers
    write(105+i,*) !Blank space
    write(105+i,H07) !Photon production vs. altitude header
    write(105+i,H08) !Charge state header
  end do
  do i=1,atmosLen
    write(106,F06) altitude(i),& !CX - TI, SC, DC
     (real(hydrogen(TI,ChS,i)+hydrogen(SC,ChS,i)+hydrogen(DC,ChS,i))/&
     norm,ChS=1,nChS)
    write(107,F06) altitude(i),& !DE - PEX
     (real(hydrogen(PEX,ChS,i))/norm,ChS=1,nChS)
  end do
!*** Stopping power
  write(108,H10) !Stopping power header
  do i=2,nSPBins !Loop through ever stopping power bin
    write(108,F07) SPBins(i)-(SPBinSize/2.0),&
      SPvsEng(i)/real(nSPions(i)**2),&
      xsTotvsEng(i)/real(nSPions(i)),&
      dEvsEng(i)/real(nSPions(i)),&
      dNvsEng(i)/real(nSPions(i)),&
      (xsTotvsEng(i)*dEvsEng(i))/real(nSPions(i)**2),&
      nSPions(i)
  end do
!***************************** Secondary Electrons *****************************
do j=1,nE2strBins !2-stream electrons, forward and backward
  write(109,F2str) (real(electFwd(i,j))/norm,i=atmosLen,1,-1)
  write(110,F2str) (real(electBwd(i,j))/norm,i=atmosLen,1,-1)
end do
!******************************* Close all files *******************************
  do i=1,nOutputFiles
    close(100+i)
  end do
  call system_clock(t4,clock_rate,clock_max) !Elapsed time for a single energy
  hrs=int(real(t4-t3)/clock_rate/3600.0)
  min=int(((real(t4-t3)/clock_rate)-hrs*3600)/60)
  sec=mod(real(t4-t3)/clock_rate,60.0)
  ! write(*,*) 'Individual run elapsed real time = ',hrs,':',min,':',sec
  deallocate(angle) !Angle variable is reallocated for each energy
end do !run=1,nEnergies

call system_clock (t2,clock_rateTotal,clock_maxTotal) !Total elapsed time
hrs=int(real(t2-t1)/clock_rateTotal/3600.0)
min=int(((real(t2-t1)/clock_rateTotal)-hrs*3600)/60)
sec=mod(real(t2-t1)/clock_rateTotal,60.0)
write(*,F3) !'**'
write(*,F2) 'Total elapsed real time = ',hrs,min,sec
10001 format(F8.2,3(2x,ES10.3E2),2x,F9.2,4(2x,I2))
end program
