
#ifdef _REAL_
    #define _MODULE_ tssm_fourier_bessel_real_2d
    #define _METHOD_ fourier_bessel_real_2d
    #define _WF_ wf_fourier_bessel_real_2d
    #define _BASE_METHOD_ polar_real_2d
    #define _BASE_WF_ wf_polar_real_2d
    #define S(x) x ## _gen_laguerre_real_2d
 #define _COMPLEX_OR_REAL_ real
#else
    #define _MODULE_ tssm_fourier_bessel_2d
    #define _METHOD_ fourier_bessel_2d
    #define _WF_ wf_fourier_bessel_2d
    #define _BASE_METHOD_ polar_2d
    #define _BASE_WF_ wf_polar_2d
    #define S(x) x ## _gen_laguerre_2d
 #define _COMPLEX_OR_REAL_ complex
#endif


module _MODULE_
    use tssm
    use tssm_grid
    use tssm_polar
    use tssm_fourier_common
    use tssm_fourier_bessel_common
    implicit none

    type, extends(_BASE_METHOD_) :: _METHOD_ 
        real(kind=prec) :: r_max = 1.0_prec
        integer :: boundary_conditions = dirichlet 
        integer :: quadrature_formula = lobatto 
        real(kind=prec), allocatable :: normalization_factors(:,:)

    contains    
        !final :: final_laguerre_1D
        !! Fortran 2003 feature final seems to be not properly implemented
        !! in the gcc/gfortran compiler :
        procedure :: finalize => S(finalize)
    end type _METHOD_

    interface _METHOD_ ! constructor
        module procedure S(new)
    end interface _METHOD_


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    type, extends(_BASE_WF_) ::  _WF_ 
    contains
        procedure :: save => S(save_wf)
        procedure :: load => S(load_wf)
        procedure :: eval => S(eval_wf)
    end type _WF_ 

    interface _WF_ ! constructor
        module procedure S(new_wf)
    end interface _WF_
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

contains


    function S(new)(M, nr, nfr, r_max, boundary_conditions, quadrature_formula) result(this)
        type(_METHOD_) :: this
        integer, intent(in) :: M
        integer, intent(in) :: nr 
        integer, intent(in) :: nfr 
        real(kind=prec), intent(in), optional :: r_max 
        integer, intent(in), optional :: boundary_conditions
        integer, intent(in), optional :: quadrature_formula
        real(kind=prec), parameter :: pi = 3.1415926535897932384626433832795028841971693993751_prec

        if (present(r_max)) then
            this%r_max = r_max
        end if
        if (present(boundary_conditions)) then
            this%boundary_conditions = boundary_conditions
            if (boundary_conditions==neumann) then
                this%quadrature_formula = radau
            endif     
        end if
        if (present(quadrature_formula)) then
            this%quadrature_formula = quadrature_formula
        endif     

        this%_BASE_METHOD_ = _BASE_METHOD_(M, nr, nfr, .true., .false. ) 
               ! symmetric coefficients
               ! not separated eigenvalues ...

        allocate( this%normalization_factors(this%nfrmin:this%nfrmax, &
                                             this%nfthetamin:this%nfthetamax) ) 

        call fourier_bessel_coeffs(nr, nfr, M, this%g%nodes_r,  this%g%weights_r, this%L, &
                                  this%eigenvalues_r_theta, this%normalization_factors, this%nfthetamin, this%nfthetamax, &
                                  this%boundary_conditions, this%quadrature_formula) 

    end function S(new)

    subroutine S(finalize)(this)
        class(_METHOD_), intent(inout) :: this

        call this%_BASE_METHOD_%finalize()
        deallocate( this%normalization_factors )

    end subroutine S(finalize)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    function S(new_wf)(m, u, coefficient) result(this)
        use, intrinsic :: iso_c_binding, only: c_f_pointer, c_ptr, c_loc
        type(_WF_) :: this
        class(_METHOD_), target, intent(inout) :: m
#ifdef _REAL_       
        real(kind=prec), optional, target, intent(inout) :: u(:,:)
        real(kind=prec), optional, intent(in) :: coefficient
#else            
        complex(kind=prec), optional, target, intent(inout) :: u(:,:)
        complex(kind=prec), optional, intent(in) :: coefficient
#endif
        this%_BASE_WF_ = _BASE_WF_(m, u, coefficient)
    end function S(new_wf)



    subroutine S(save_wf)(this, filename)
#ifdef _NO_HDF5_
        class(_WF_), intent(inout) :: this
        character(len=*), intent(in) :: filename
        print *, "W: save not implemented"
#else
        use tssm_hdf5
        class(_WF_), intent(inout) :: this
        character(len=*), intent(in) :: filename
        !TODO

        call this%_BASE_WF_%save(filename)

        select type (m=>this%m ); class is (_METHOD_)
        call hdf5_write_attributes(filename, (/ "nodes_type" /), &
          (/ "fourier_bessel" /), &
          (/ character(len=0) :: /), (/ integer :: /), &
          (/ "r_max" /), (/ m%r_max /) ) 
        end select
!TODO save nodes !!!
#endif        
    end subroutine S(save_wf)


   subroutine S(load_wf)(this, filename)
#ifdef _NO_HDF5_
        class(_WF_), intent(inout) :: this
        character(len=*), intent(in) :: filename
        print *, "W: load not implemented"
#else
        use tssm_hdf5
        class(_WF_), intent(inout) :: this
        character(len=*), intent(in) :: filename
#ifdef _QUADPRECISION_
        real(kind=prec), parameter :: eps = epsilon(1.0_8)
#else        
        real(kind=prec), parameter :: eps = epsilon(1.0_prec)
#endif
        character(len=20) :: s
        integer :: n, len

       call hdf5_read_string_attribute(filename, "nodes_type", s, len)      
       if (s(1:len)/="fourier_bessel") then
              stop "E: wrong nodes type"
       end if
       select type (m=>this%m ); class is (_METHOD_)
       if (abs(hdf5_read_double_attribute(filename, "r_max")- m%r_max)>eps) then
              stop "E: incompatible grids"
       end if       
       end select

       call this%_BASE_WF_%save(filename)
#endif
    end subroutine S(load_wf)

    function S(eval_wf)(this, x, y) result(z)
        class(_WF_), intent(inout) :: this
        real(kind=prec), intent(in) :: x, y
        _COMPLEX_OR_REAL_(kind=prec) :: z

        real(kind=prec) :: r, r2, theta, f, lambda
        complex(kind=prec) :: s
        integer :: j, m, m1

        select type (mm =>this%m ); class is (_METHOD_)

        r2 = x**2 + y**2
        z = 0.0_prec
        if (r2 > mm%r_max) then
            return
        end if

        r = sqrt(r2)
        theta = atan2(y, x)
        call this%to_frequency_space

#ifdef _REAL_                
        do m = this%m%nfthetamin, this%m%nfthetamax
            if (m==0) then
                do j = this%m%nfrmin, this%m%nfrmax
                    lambda = sqrt(this%m%eigenvalues_r_theta(j, m))
                    f = mm%normalization_factors(j, m)
                    z = z + f*bessel_jn(m, lambda*r) * this%ufc(j, m)
                end do    
            else
                s = 0.0_prec
                do j = this%m%nfrmin, this%m%nfrmax
                    lambda = sqrt(this%m%eigenvalues_r_theta(j, m))
                    f = mm%normalization_factors(j, m)
                    s = s + f*bessel_jn(m, lambda*r) * this%ufc(j, m)
                end do
                z = z + 2.0_prec*real(exp(cmplx(0.0_prec, m*theta, kind=prec)) * s, kind=prec)
            end if
        end do
#else
        do m = this%m%nfthetamin, this%m%nfthetamax
            m1 = m
            if (m1>this%m%g%ntheta/2) then
                m1 = abs(m1-this%m%g%ntheta)
            end if
            s = 0.0_prec
            do j = this%m%nfrmin, this%m%nfrmax
                lambda = sqrt(this%m%eigenvalues_r_theta(j, m1))
                f = mm%normalization_factors(j, m1)
                s = s + f*bessel_jn(m1, lambda*r) * this%uf(j, m)
            end do
            z = z + exp(cmplx(0.0_prec, m*theta, kind=prec)) * s
        end do
#endif                
        end select
        
    end function S(eval_wf)


end module _MODULE_ 
